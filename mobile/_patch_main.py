"""Patch script to add chain endpoints to advx26-backend/app/main.py"""
import pathlib
import sys

target = pathlib.Path(r"C:\Users\lazy_lz\Desktop\advx26-backend\app\main.py")
content = target.read_text(encoding="utf-8")

# Step 1: Add uuid4 import
old_imports = """from __future__ import annotations

import asyncio
import re
import sqlite3
from contextlib import asynccontextmanager, suppress
from datetime import datetime, timezone
from typing import Annotated"""

new_imports = """from __future__ import annotations

import asyncio
import re
import sqlite3
from contextlib import asynccontextmanager, suppress
from datetime import datetime, timezone
from typing import Annotated
from uuid import uuid4"""

if "from uuid import uuid4" not in content:
    content = content.replace(old_imports, new_imports)

# Step 2: Add chain schema imports
old_schemas = """from .schemas import (
    ContentCreated,
    ContentList,
    ContentPage,
    ContentSource,
    ContentSummary,
    EmailLoginRequest,
    EmailRegisterRequest,
    EmailRegistered,
    HealthResponse,
    ReadinessResponse,
    UserProfile,
    UserTokenIssued,
    WalletChallengeRequest,
    WalletChallengeResponse,
    WalletTokenIssued,
    WalletVerifyRequest,
)"""

new_schemas = """from .chain_service import ChainService
from .schemas import (
    ChainStatusResponse,
    ContentCreated,
    ContentList,
    ContentPage,
    ContentSource,
    ContentSummary,
    EditionResponse,
    EditionsListResponse,
    EmailLoginRequest,
    EmailRegisterRequest,
    EmailRegistered,
    HealthResponse,
    MintResultResponse,
    PrepareMintResponse,
    ReadinessResponse,
    SubmitSignedRequest,
    TokenMetadataResponse,
    UserProfile,
    UserTokenIssued,
    WalletChallengeRequest,
    WalletChallengeResponse,
    WalletTokenIssued,
    WalletVerifyRequest,
)"""

if "from .chain_service import ChainService" not in content:
    content = content.replace(old_schemas, new_schemas)

# Step 3: Add ChainService initialization
old_cleanup = """    cleanup = StagingCleanup(
        database=database,
        object_store=object_store,
        failed_retention_seconds=settings.failed_staging_retention_seconds,
        failed_max_bytes=settings.failed_staging_max_bytes,
    )"""

new_cleanup = """    cleanup = StagingCleanup(
        database=database,
        object_store=object_store,
        failed_retention_seconds=settings.failed_staging_retention_seconds,
        failed_max_bytes=settings.failed_staging_max_bytes,
    )
    chain_service: ChainService | None = None
    if settings.chain_enabled and settings.chain_contract_address:
        chain_service = ChainService(
            rpc_url=settings.chain_rpc_url,
            chain_id=settings.chain_id,
            contract_address=settings.chain_contract_address,
            operator_key=settings.chain_operator_private_key,
        )"""

if "chain_service: ChainService | None = None" not in content:
    content = content.replace(old_cleanup, new_cleanup)

# Step 4: Add chain endpoints before install_openapi
old_tail = "    install_openapi(app, public_base_url=settings.public_base_url)\n    return app"

chain_endpoints = '''    # --- Chain endpoints -------------------------------------------------------

    def _require_chain() -> ChainService:
        if chain_service is None or not settings.chain_enabled:
            raise HTTPException(status_code=503, detail="Chain service not enabled")
        return chain_service

    def _get_user_row(user: UserPrincipal) -> sqlite3.Row:
        row = database.get_user(user.user_id)
        if row is None:
            raise HTTPException(status_code=401, detail="\u65e0\u6548\u6216\u7f3a\u5c11\u7528\u6237 Token")
        return row

    def _get_content_for_chain(content_id: str) -> sqlite3.Row:
        with database.connect() as conn:
            row = conn.execute(
                "SELECT * FROM contents WHERE id = ? AND state != 'DELETED'",
                (content_id,),
            ).fetchone()
        if row is None:
            raise HTTPException(status_code=404, detail="\u5185\u5bb9\u4e0d\u5b58\u5728")
        return row

    def _get_chain_row(content_id: str) -> sqlite3.Row | None:
        with database.connect() as conn:
            return conn.execute(
                "SELECT * FROM content_chain WHERE content_id = ?",
                (content_id,),
            ).fetchone()

    def _build_token_uri(content_id: str) -> str:
        return f"{settings.public_base_url}/api/v1/contents/{content_id}/token-metadata"

    def _resolve_signing_key(user_row: sqlite3.Row) -> str:
        private_key = user_row["private_key"] if "private_key" in user_row.keys() else None
        if private_key:
            return private_key
        return settings.chain_operator_private_key

    @app.get(
        "/api/v1/contents/{content_id}/chain",
        response_model=ChainStatusResponse,
        responses=error_responses(401, 404, 503),
        tags=["contents"],
        summary="Get chain status for content",
        operation_id="getContentChainStatus",
    )
    async def get_chain_status(
        content_id: str,
        response: Response,
        user: UserPrincipal = Depends(require_user),
    ) -> ChainStatusResponse:
        _require_content_id(content_id)
        _require_chain()
        _get_content_for_chain(content_id)
        chain_row = _get_chain_row(content_id)
        response.headers["Cache-Control"] = "no-store"
        if chain_row is None:
            return ChainStatusResponse(content_id=content_id, chain_state="NONE")
        return ChainStatusResponse(
            content_id=content_id,
            chain_state=chain_row["chain_state"],
            token_id=chain_row["token_id"],
            tx_hash=chain_row["tx_hash"],
            contract_address=chain_row["contract_address"],
            token_uri=chain_row["token_uri"],
            owner_wallet=chain_row["owner_wallet"],
            error_message=chain_row["error_message"],
            minted_at=chain_row["minted_at"],
        )

    @app.post(
        "/api/v1/contents/{content_id}/chain/mint",
        response_model=MintResultResponse,
        responses=error_responses(400, 401, 404, 409, 500, 503),
        tags=["contents"],
        summary="Mint content as NFT (server-side signing)",
        operation_id="mintContentNFT",
    )
    async def mint_content(
        content_id: str,
        response: Response,
        user: UserPrincipal = Depends(require_user),
    ) -> MintResultResponse:
        _require_content_id(content_id)
        svc = _require_chain()
        user_row = _get_user_row(user)
        content_row = _get_content_for_chain(content_id)
        if content_row["state"] != "READY":
            raise HTTPException(status_code=400, detail="\u5185\u5bb9\u5c1a\u672a\u5c31\u7eea")
        if content_row["owner_user_id"] != user.user_id:
            raise HTTPException(status_code=404, detail="\u5185\u5bb9\u4e0d\u5b58\u5728")
        wallet_address = user_row["wallet_address"]
        if not wallet_address:
            raise HTTPException(status_code=400, detail="\u7528\u6237\u672a\u7ed1\u5b9a\u94b1\u5305\u5730\u5740")

        chain_row = _get_chain_row(content_id)
        if chain_row is not None:
            if chain_row["chain_state"] == "MINTED":
                response.headers["Cache-Control"] = "no-store"
                return MintResultResponse(
                    content_id=content_id,
                    token_id=chain_row["token_id"],
                    tx_hash=chain_row["tx_hash"],
                    contract_address=chain_row["contract_address"],
                    chain_state="MINTED",
                )
            if chain_row["chain_state"] == "MINTING":
                raise HTTPException(status_code=409, detail="\u5185\u5bb9\u6b63\u5728\u94f8\u9020\u4e2d")

        now = utc_string(datetime.now(timezone.utc))
        token_uri = _build_token_uri(content_id)
        with database.connect() as conn:
            conn.execute(
                """
                INSERT INTO content_chain (content_id, chain_state, created_at, updated_at)
                VALUES (?, 'MINTING', ?, ?)
                ON CONFLICT(content_id) DO UPDATE SET
                    chain_state = 'MINTING', updated_at = excluded.updated_at
                """,
                (content_id, now, now),
            )

        signing_key = _resolve_signing_key(user_row)
        try:
            token_id, tx_hash = svc.mint_server_side(wallet_address, token_uri, signing_key)
        except Exception as exc:
            error_msg = str(exc)
            with database.connect() as conn:
                conn.execute(
                    """
                    UPDATE content_chain
                    SET chain_state = 'FAILED', error_message = ?, updated_at = ?
                    WHERE content_id = ?
                    """,
                    (error_msg, utc_string(datetime.now(timezone.utc)), content_id),
                )
            raise HTTPException(status_code=500, detail=f"\u94fe\u4e0a\u94f8\u9020\u5931\u8d25: {error_msg}") from exc

        minted_at = utc_string(datetime.now(timezone.utc))
        with database.connect() as conn:
            conn.execute(
                """
                UPDATE content_chain
                SET chain_state = 'MINTED', token_id = ?, tx_hash = ?,
                    contract_address = ?, token_uri = ?, owner_wallet = ?,
                    minted_at = ?, error_message = NULL, updated_at = ?
                WHERE content_id = ?
                """,
                (token_id, tx_hash, svc.contract_address, token_uri, wallet_address, minted_at, minted_at, content_id),
            )
            conn.execute(
                """
                INSERT INTO content_editions (id, content_id, token_id, tx_hash, owner_wallet, token_uri, edition_type, minted_at)
                VALUES (?, ?, ?, ?, ?, ?, 'CREATOR', ?)
                """,
                (uuid4().hex, content_id, token_id, tx_hash, wallet_address, token_uri, minted_at),
            )

        response.headers["Cache-Control"] = "no-store"
        return MintResultResponse(
            content_id=content_id,
            token_id=token_id,
            tx_hash=tx_hash,
            contract_address=svc.contract_address,
            chain_state="MINTED",
        )

    @app.post(
        "/api/v1/contents/{content_id}/chain/prepare-mint",
        response_model=PrepareMintResponse,
        responses=error_responses(400, 401, 404, 409, 503),
        tags=["contents"],
        summary="Prepare unsigned mint transaction for client signing",
        operation_id="prepareMintContent",
    )
    async def prepare_mint_content(
        content_id: str,
        response: Response,
        user: UserPrincipal = Depends(require_user),
    ) -> PrepareMintResponse:
        _require_content_id(content_id)
        svc = _require_chain()
        user_row = _get_user_row(user)
        content_row = _get_content_for_chain(content_id)
        if content_row["state"] != "READY":
            raise HTTPException(status_code=400, detail="\u5185\u5bb9\u5c1a\u672a\u5c31\u7eea")
        if content_row["owner_user_id"] != user.user_id:
            raise HTTPException(status_code=404, detail="\u5185\u5bb9\u4e0d\u5b58\u5728")
        wallet_address = user_row["wallet_address"]
        if not wallet_address:
            raise HTTPException(status_code=400, detail="\u7528\u6237\u672a\u7ed1\u5b9a\u94b1\u5305\u5730\u5740")

        chain_row = _get_chain_row(content_id)
        if chain_row is not None and chain_row["chain_state"] not in ("NONE", "FAILED"):
            raise HTTPException(status_code=409, detail="\u5185\u5bb9\u5df2\u4e0a\u94fe\u6216\u6b63\u5728\u94f8\u9020\u4e2d")

        token_uri = _build_token_uri(content_id)
        tx = svc.build_mint_tx(wallet_address, token_uri, wallet_address)
        response.headers["Cache-Control"] = "no-store"
        return PrepareMintResponse(
            to=tx["to"],
            data=tx["data"],
            nonce=tx["nonce"],
            gas=tx["gas"],
            gas_price=tx["gas_price"],
            chain_id=tx["chain_id"],
            value=tx["value"],
            token_uri=token_uri,
        )

    @app.post(
        "/api/v1/contents/{content_id}/chain/submit-signed",
        response_model=MintResultResponse,
        responses=error_responses(400, 401, 404, 409, 500, 503),
        tags=["contents"],
        summary="Submit a client-signed mint transaction",
        operation_id="submitSignedMint",
    )
    async def submit_signed_mint(
        content_id: str,
        payload: SubmitSignedRequest,
        response: Response,
        user: UserPrincipal = Depends(require_user),
    ) -> MintResultResponse:
        _require_content_id(content_id)
        svc = _require_chain()
        user_row = _get_user_row(user)
        content_row = _get_content_for_chain(content_id)
        if content_row["state"] != "READY":
            raise HTTPException(status_code=400, detail="\u5185\u5bb9\u5c1a\u672a\u5c31\u7eea")
        if content_row["owner_user_id"] != user.user_id:
            raise HTTPException(status_code=404, detail="\u5185\u5bb9\u4e0d\u5b58\u5728")
        wallet_address = user_row["wallet_address"]
        if not wallet_address:
            raise HTTPException(status_code=400, detail="\u7528\u6237\u672a\u7ed1\u5b9a\u94b1\u5305\u5730\u5740")

        chain_row = _get_chain_row(content_id)
        if chain_row is not None and chain_row["chain_state"] not in ("NONE", "MINTING", "FAILED"):
            raise HTTPException(status_code=409, detail="\u5185\u5bb9\u5df2\u4e0a\u94fe")

        now = utc_string(datetime.now(timezone.utc))
        token_uri = _build_token_uri(content_id)
        with database.connect() as conn:
            conn.execute(
                """
                INSERT INTO content_chain (content_id, chain_state, created_at, updated_at)
                VALUES (?, 'MINTING', ?, ?)
                ON CONFLICT(content_id) DO UPDATE SET
                    chain_state = 'MINTING', updated_at = excluded.updated_at
                """,
                (content_id, now, now),
            )

        try:
            tx_hash = svc.send_raw_tx(payload.raw_tx)
            receipt = svc.wait_for_receipt(tx_hash)
            token_id = svc._extract_token_id(receipt)
        except Exception as exc:
            error_msg = str(exc)
            with database.connect() as conn:
                conn.execute(
                    """
                    UPDATE content_chain
                    SET chain_state = 'FAILED', error_message = ?, updated_at = ?
                    WHERE content_id = ?
                    """,
                    (error_msg, utc_string(datetime.now(timezone.utc)), content_id),
                )
            raise HTTPException(status_code=500, detail=f"\u94fe\u4e0a\u4ea4\u6613\u5931\u8d25: {error_msg}") from exc

        minted_at = utc_string(datetime.now(timezone.utc))
        with database.connect() as conn:
            conn.execute(
                """
                UPDATE content_chain
                SET chain_state = 'MINTED', token_id = ?, tx_hash = ?,
                    contract_address = ?, token_uri = ?, owner_wallet = ?,
                    minted_at = ?, error_message = NULL, updated_at = ?
                WHERE content_id = ?
                """,
                (token_id, tx_hash, svc.contract_address, token_uri, wallet_address, minted_at, minted_at, content_id),
            )
            conn.execute(
                """
                INSERT INTO content_editions (id, content_id, token_id, tx_hash, owner_wallet, token_uri, edition_type, minted_at)
                VALUES (?, ?, ?, ?, ?, ?, 'CREATOR', ?)
                """,
                (uuid4().hex, content_id, token_id, tx_hash, wallet_address, token_uri, minted_at),
            )

        response.headers["Cache-Control"] = "no-store"
        return MintResultResponse(
            content_id=content_id,
            token_id=token_id,
            tx_hash=tx_hash,
            contract_address=svc.contract_address,
            chain_state="MINTED",
        )

    @app.post(
        "/api/v1/contents/{content_id}/claim",
        response_model=MintResultResponse,
        responses=error_responses(400, 401, 404, 500, 503),
        tags=["contents"],
        summary="Claim an edition of minted content (server-side signing)",
        operation_id="claimContentEdition",
    )
    async def claim_content(
        content_id: str,
        response: Response,
        user: UserPrincipal = Depends(require_user),
    ) -> MintResultResponse:
        _require_content_id(content_id)
        svc = _require_chain()
        user_row = _get_user_row(user)
        _get_content_for_chain(content_id)
        wallet_address = user_row["wallet_address"]
        if not wallet_address:
            raise HTTPException(status_code=400, detail="\u7528\u6237\u672a\u7ed1\u5b9a\u94b1\u5305\u5730\u5740")

        chain_row = _get_chain_row(content_id)
        if chain_row is None or chain_row["chain_state"] != "MINTED":
            raise HTTPException(status_code=400, detail="\u5185\u5bb9\u5c1a\u672a\u4e0a\u94fe")

        # Idempotent: if user already claimed, return existing edition
        with database.connect() as conn:
            existing = conn.execute(
                "SELECT * FROM content_editions WHERE content_id = ? AND owner_wallet = ?",
                (content_id, wallet_address),
            ).fetchone()
        if existing is not None:
            response.headers["Cache-Control"] = "no-store"
            return MintResultResponse(
                content_id=content_id,
                token_id=existing["token_id"],
                tx_hash=existing["tx_hash"],
                contract_address=svc.contract_address,
                chain_state="MINTED",
            )

        signing_key = _resolve_signing_key(user_row)
        token_uri = _build_token_uri(content_id)
        try:
            token_id, tx_hash = svc.mint_server_side(wallet_address, token_uri, signing_key)
        except Exception as exc:
            raise HTTPException(status_code=500, detail=f"\u94fe\u4e0a\u94f8\u9020\u5931\u8d25: {exc}") from exc

        minted_at = utc_string(datetime.now(timezone.utc))
        with database.connect() as conn:
            conn.execute(
                """
                INSERT INTO content_editions (id, content_id, token_id, tx_hash, owner_wallet, token_uri, edition_type, minted_at)
                VALUES (?, ?, ?, ?, ?, ?, 'CLAIM', ?)
                """,
                (uuid4().hex, content_id, token_id, tx_hash, wallet_address, token_uri, minted_at),
            )

        response.headers["Cache-Control"] = "no-store"
        return MintResultResponse(
            content_id=content_id,
            token_id=token_id,
            tx_hash=tx_hash,
            contract_address=svc.contract_address,
            chain_state="MINTED",
        )

    @app.post(
        "/api/v1/contents/{content_id}/claim/prepare",
        response_model=PrepareMintResponse,
        responses=error_responses(400, 401, 404, 409, 503),
        tags=["contents"],
        summary="Prepare unsigned claim transaction for client signing",
        operation_id="prepareClaimEdition",
    )
    async def prepare_claim(
        content_id: str,
        response: Response,
        user: UserPrincipal = Depends(require_user),
    ) -> PrepareMintResponse:
        _require_content_id(content_id)
        svc = _require_chain()
        user_row = _get_user_row(user)
        _get_content_for_chain(content_id)
        wallet_address = user_row["wallet_address"]
        if not wallet_address:
            raise HTTPException(status_code=400, detail="\u7528\u6237\u672a\u7ed1\u5b9a\u94b1\u5305\u5730\u5740")

        chain_row = _get_chain_row(content_id)
        if chain_row is None or chain_row["chain_state"] != "MINTED":
            raise HTTPException(status_code=400, detail="\u5185\u5bb9\u5c1a\u672a\u4e0a\u94fe")

        with database.connect() as conn:
            existing = conn.execute(
                "SELECT * FROM content_editions WHERE content_id = ? AND owner_wallet = ?",
                (content_id, wallet_address),
            ).fetchone()
        if existing is not None:
            raise HTTPException(status_code=409, detail="\u5df2\u9886\u53d6\u8fc7\u8be5\u5185\u5bb9\u7684\u7248\u672c")

        token_uri = _build_token_uri(content_id)
        tx = svc.build_mint_tx(wallet_address, token_uri, wallet_address)
        response.headers["Cache-Control"] = "no-store"
        return PrepareMintResponse(
            to=tx["to"],
            data=tx["data"],
            nonce=tx["nonce"],
            gas=tx["gas"],
            gas_price=tx["gas_price"],
            chain_id=tx["chain_id"],
            value=tx["value"],
            token_uri=token_uri,
        )

    @app.post(
        "/api/v1/contents/{content_id}/claim/submit-signed",
        response_model=MintResultResponse,
        responses=error_responses(400, 401, 404, 409, 500, 503),
        tags=["contents"],
        summary="Submit a client-signed claim transaction",
        operation_id="submitSignedClaim",
    )
    async def submit_signed_claim(
        content_id: str,
        payload: SubmitSignedRequest,
        response: Response,
        user: UserPrincipal = Depends(require_user),
    ) -> MintResultResponse:
        _require_content_id(content_id)
        svc = _require_chain()
        user_row = _get_user_row(user)
        _get_content_for_chain(content_id)
        wallet_address = user_row["wallet_address"]
        if not wallet_address:
            raise HTTPException(status_code=400, detail="\u7528\u6237\u672a\u7ed1\u5b9a\u94b1\u5305\u5730\u5740")

        chain_row = _get_chain_row(content_id)
        if chain_row is None or chain_row["chain_state"] != "MINTED":
            raise HTTPException(status_code=400, detail="\u5185\u5bb9\u5c1a\u672a\u4e0a\u94fe")

        with database.connect() as conn:
            existing = conn.execute(
                "SELECT * FROM content_editions WHERE content_id = ? AND owner_wallet = ?",
                (content_id, wallet_address),
            ).fetchone()
        if existing is not None:
            raise HTTPException(status_code=409, detail="\u5df2\u9886\u53d6\u8fc7\u8be5\u5185\u5bb9\u7684\u7248\u672c")

        try:
            tx_hash = svc.send_raw_tx(payload.raw_tx)
            receipt = svc.wait_for_receipt(tx_hash)
            token_id = svc._extract_token_id(receipt)
        except Exception as exc:
            raise HTTPException(status_code=500, detail=f"\u94fe\u4e0a\u4ea4\u6613\u5931\u8d25: {exc}") from exc

        token_uri = _build_token_uri(content_id)
        minted_at = utc_string(datetime.now(timezone.utc))
        with database.connect() as conn:
            conn.execute(
                """
                INSERT INTO content_editions (id, content_id, token_id, tx_hash, owner_wallet, token_uri, edition_type, minted_at)
                VALUES (?, ?, ?, ?, ?, ?, 'CLAIM', ?)
                """,
                (uuid4().hex, content_id, token_id, tx_hash, wallet_address, token_uri, minted_at),
            )

        response.headers["Cache-Control"] = "no-store"
        return MintResultResponse(
            content_id=content_id,
            token_id=token_id,
            tx_hash=tx_hash,
            contract_address=svc.contract_address,
            chain_state="MINTED",
        )

    @app.get(
        "/api/v1/contents/{content_id}/token-metadata",
        response_model=TokenMetadataResponse,
        responses=error_responses(404),
        tags=["contents"],
        summary="Public ERC-721 token metadata",
        operation_id="getTokenMetadata",
    )
    async def token_metadata(content_id: str) -> TokenMetadataResponse:
        _require_content_id(content_id)
        with database.connect() as conn:
            content_row = conn.execute(
                "SELECT * FROM contents WHERE id = ? AND state != 'DELETED'",
                (content_id,),
            ).fetchone()
        if content_row is None:
            raise HTTPException(status_code=404, detail="\u5185\u5bb9\u4e0d\u5b58\u5728")
        return TokenMetadataResponse(
            name=f"SoundPola: {content_row['display_label']}",
            description=f"Sound memory #{content_id[:8]} - {content_row['duration_ms']}ms",
            image=f"{settings.public_base_url}/api/v1/contents/{content_id}/assets/video",
            attributes=[
                {"trait_type": "Duration", "value": f"{content_row['duration_ms']}ms"},
                {"trait_type": "Content ID", "value": content_id},
                {"trait_type": "Created", "value": content_row["created_at"]},
            ],
        )

    @app.get(
        "/api/v1/contents/{content_id}/editions",
        response_model=EditionsListResponse,
        responses=error_responses(401, 404, 503),
        tags=["contents"],
        summary="List editions for content",
        operation_id="listContentEditions",
    )
    async def list_editions(
        content_id: str,
        response: Response,
        user: UserPrincipal = Depends(require_user),
    ) -> EditionsListResponse:
        _require_content_id(content_id)
        _require_chain()
        _get_content_for_chain(content_id)
        with database.connect() as conn:
            rows = conn.execute(
                "SELECT * FROM content_editions WHERE content_id = ? ORDER BY minted_at",
                (content_id,),
            ).fetchall()
        response.headers["Cache-Control"] = "no-store"
        return EditionsListResponse(
            content_id=content_id,
            editions=[
                EditionResponse(
                    id=row["id"],
                    content_id=row["content_id"],
                    token_id=row["token_id"],
                    tx_hash=row["tx_hash"],
                    owner_wallet=row["owner_wallet"],
                    token_uri=row["token_uri"],
                    edition_type=row["edition_type"],
                    minted_at=row["minted_at"],
                )
                for row in rows
            ],
        )

    install_openapi(app, public_base_url=settings.public_base_url)
    return app'''

if "# --- Chain endpoints" not in content:
    content = content.replace(old_tail, chain_endpoints)

target.write_text(content, encoding="utf-8")
print("SUCCESS: All chain endpoints added to main.py")
