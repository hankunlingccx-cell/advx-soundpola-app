from pathlib import Path

p = Path(r"d:\vibecoding\advx\advx-soundpola-app\mobile\lib\screens\collection\category_play_screen.dart")
lines = p.read_text(encoding="utf-8").splitlines(True)
# line 1032 is index 1031 - fix garbled cancel
for i, line in enumerate(lines):
    if "TextButton(" in line and i + 3 < len(lines):
        # look ahead for child const Text with bad encoding
        chunk = "".join(lines[i : i + 6])
        if "Navigator.of(context).pop()" in chunk and "取消" not in chunk and "保存" not in chunk:
            for j in range(i, min(i + 8, len(lines))):
                if "child: const Text(" in lines[j] and j + 1 < len(lines):
                    # next line should be the string
                    if "取消" not in lines[j + 1] and "'" in lines[j + 1]:
                        lines[j + 1] = "            '取消',\n"
                        print("fixed cancel at", j + 2)
                        break

p.write_text("".join(lines), encoding="utf-8")
print("wrote")
