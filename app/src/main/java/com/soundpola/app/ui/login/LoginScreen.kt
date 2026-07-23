package com.soundpola.app.ui.login

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.blur
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.input.VisualTransformation
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import com.soundpola.app.R
import com.soundpola.app.ui.theme.Accent
import com.soundpola.app.ui.theme.Black
import com.soundpola.app.ui.theme.BodyStyle
import com.soundpola.app.ui.theme.CaptionStyle
import com.soundpola.app.ui.theme.InputBackground
import com.soundpola.app.ui.theme.Placeholder
import com.soundpola.app.ui.theme.SoundpolaTheme
import com.soundpola.app.ui.theme.TitleStyle
import com.soundpola.app.ui.theme.White

/**
 * Login screen restored from Figma node 63:77
 * https://www.figma.com/design/uXCTF78KramsNbQQXTiMji/Untitled?node-id=63-77
 */
@Composable
fun LoginScreen(
    onLoginClick: (account: String, password: String, remember: Boolean) -> Unit = { _, _, _ -> },
    onForgetPasswordClick: () -> Unit = {},
) {
    var account by remember { mutableStateOf("") }
    var password by remember { mutableStateOf("") }
    var rememberMe by remember { mutableStateOf(false) }

    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(Black),
    ) {
        BottomGlowDecoration(
            modifier = Modifier
                .align(Alignment.BottomCenter)
                .fillMaxWidth()
                .height(320.dp),
        )

        Column(
            modifier = Modifier
                .fillMaxSize()
                .statusBarsPadding()
                .navigationBarsPadding()
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 26.dp),
        ) {
            // Figma: title at y≈183 on iPhone 16 (~393×852)
            Spacer(modifier = Modifier.height(120.dp))

            Text(
                text = stringResource(R.string.sign_in_title),
                style = TitleStyle,
                textAlign = TextAlign.Start,
                modifier = Modifier
                    .padding(start = 4.dp)
                    .width(230.dp),
            )

            Spacer(modifier = Modifier.height(41.dp))

            Column(
                modifier = Modifier.fillMaxWidth(),
                verticalArrangement = Arrangement.spacedBy(40.dp),
            ) {
                Column(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.spacedBy(19.dp),
                ) {
                    Column(
                        modifier = Modifier.fillMaxWidth(),
                        verticalArrangement = Arrangement.spacedBy(20.dp),
                    ) {
                        LoginInputField(
                            value = account,
                            onValueChange = { account = it },
                            hint = stringResource(R.string.account_hint),
                            iconRes = R.drawable.ic_account,
                            keyboardType = KeyboardType.Email,
                        )
                        LoginInputField(
                            value = password,
                            onValueChange = { password = it },
                            hint = stringResource(R.string.password_hint),
                            iconRes = R.drawable.ic_password,
                            keyboardType = KeyboardType.Password,
                            isPassword = true,
                        )
                    }

                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.SpaceBetween,
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        RememberMeRow(
                            checked = rememberMe,
                            onCheckedChange = { rememberMe = it },
                        )
                        Text(
                            text = stringResource(R.string.forget_password),
                            style = CaptionStyle.copy(color = Accent),
                            modifier = Modifier.clickable(
                                indication = null,
                                interactionSource = remember { MutableInteractionSource() },
                                onClick = onForgetPasswordClick,
                            ),
                        )
                    }
                }

                LoginButton(
                    onClick = { onLoginClick(account, password, rememberMe) },
                )
            }

            Spacer(modifier = Modifier.height(48.dp))

            OrDivider()

            Spacer(modifier = Modifier.height(120.dp))
        }
    }
}

@Composable
private fun LoginInputField(
    value: String,
    onValueChange: (String) -> Unit,
    hint: String,
    iconRes: Int,
    keyboardType: KeyboardType,
    isPassword: Boolean = false,
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .height(52.dp)
            .background(InputBackground, RoundedCornerShape(30.dp))
            .padding(start = 20.dp, end = 20.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(20.dp),
    ) {
        Icon(
            painter = painterResource(iconRes),
            contentDescription = null,
            tint = White.copy(alpha = 0.4f),
            modifier = Modifier.size(20.dp),
        )
        Box(modifier = Modifier.weight(1f)) {
            if (value.isEmpty()) {
                Text(
                    text = hint,
                    style = BodyStyle.copy(color = Placeholder),
                )
            }
            BasicTextField(
                value = value,
                onValueChange = onValueChange,
                singleLine = true,
                textStyle = BodyStyle,
                cursorBrush = SolidColor(Accent),
                visualTransformation = if (isPassword) {
                    PasswordVisualTransformation()
                } else {
                    VisualTransformation.None
                },
                keyboardOptions = KeyboardOptions(keyboardType = keyboardType),
                modifier = Modifier.fillMaxWidth(),
            )
        }
    }
}

@Composable
private fun RememberMeRow(
    checked: Boolean,
    onCheckedChange: (Boolean) -> Unit,
) {
    Row(
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(5.dp),
        modifier = Modifier.clickable(
            indication = null,
            interactionSource = remember { MutableInteractionSource() },
            onClick = { onCheckedChange(!checked) },
        ),
    ) {
        Box(
            modifier = Modifier
                .size(16.dp)
                .border(1.dp, White, RoundedCornerShape(4.dp))
                .background(
                    if (checked) Accent else Color.Transparent,
                    RoundedCornerShape(4.dp),
                ),
            contentAlignment = Alignment.Center,
        ) {
            if (checked) {
                Canvas(modifier = Modifier.size(10.dp)) {
                    val stroke = 1.5.dp.toPx()
                    drawLine(
                        color = Black,
                        start = Offset(size.width * 0.15f, size.height * 0.5f),
                        end = Offset(size.width * 0.4f, size.height * 0.75f),
                        strokeWidth = stroke,
                    )
                    drawLine(
                        color = Black,
                        start = Offset(size.width * 0.4f, size.height * 0.75f),
                        end = Offset(size.width * 0.85f, size.height * 0.25f),
                        strokeWidth = stroke,
                    )
                }
            }
        }
        Text(
            text = stringResource(R.string.remember_me),
            style = CaptionStyle,
        )
    }
}

@Composable
private fun LoginButton(onClick: () -> Unit) {
    Box(
        modifier = Modifier
            .fillMaxWidth()
            .height(54.dp)
            .background(Accent, RoundedCornerShape(30.dp))
            .clickable(
                indication = null,
                interactionSource = remember { MutableInteractionSource() },
                onClick = onClick,
            ),
        contentAlignment = Alignment.Center,
    ) {
        Text(
            text = stringResource(R.string.login),
            style = BodyStyle.copy(color = Black),
        )
    }
}

@Composable
private fun OrDivider() {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 0.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.SpaceBetween,
    ) {
        Box(
            modifier = Modifier
                .weight(1f)
                .height(1.dp)
                .background(White.copy(alpha = 0.6f), RoundedCornerShape(7.dp)),
        )
        Text(
            text = stringResource(R.string.or),
            style = CaptionStyle.copy(color = White.copy(alpha = 0.6f)),
            modifier = Modifier.padding(horizontal = 12.dp),
        )
        Box(
            modifier = Modifier
                .weight(1f)
                .height(1.dp)
                .background(White.copy(alpha = 0.6f), RoundedCornerShape(7.dp)),
        )
    }
}

@Composable
private fun BottomGlowDecoration(modifier: Modifier = Modifier) {
    // Figma node 65:222 — large blurred decorative blob at bottom
    Canvas(
        modifier = modifier.blur(100.dp),
    ) {
        val w = size.width
        val h = size.height
        drawCircle(
            brush = Brush.radialGradient(
                colors = listOf(
                    Accent.copy(alpha = 0.55f),
                    Accent.copy(alpha = 0.2f),
                    Color.Transparent,
                ),
                center = Offset(w * 0.35f, h * 0.55f),
                radius = w * 0.55f,
            ),
            center = Offset(w * 0.35f, h * 0.55f),
            radius = w * 0.55f,
        )
        drawCircle(
            brush = Brush.radialGradient(
                colors = listOf(
                    Color(0xFF3AAF9A).copy(alpha = 0.4f),
                    Color.Transparent,
                ),
                center = Offset(w * 0.7f, h * 0.7f),
                radius = w * 0.45f,
            ),
            center = Offset(w * 0.7f, h * 0.7f),
            radius = w * 0.45f,
        )
    }
}

@Preview(showBackground = true, backgroundColor = 0xFF000000, widthDp = 393, heightDp = 852)
@Composable
private fun LoginScreenPreview() {
    SoundpolaTheme {
        LoginScreen()
    }
}
