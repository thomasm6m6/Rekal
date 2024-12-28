import subprocess
import tempfile
from datetime import datetime, timezone
from pathlib import Path

root_dir = Path.home() / "ss"
img_dir = root_dir / "img"
full_dir = root_dir / "full"
small_dir = root_dir / "small"

def ocr(fpath):
    cmd = ["ocr", str(fpath / "image.png")]
    result = subprocess.check_output(cmd).decode()
    with open(fpath / "ocr.txt", 'w') as f:
        f.write(result)

def encode(blk_len):
    files = {}
    now = int(datetime.now(timezone.utc).timestamp())

    for d in img_dir.iterdir():
        if not d.is_dir():
            continue

        n = int(d.name)
        if now - n < blk_len:
            continue

        block = n//blk_len * blk_len
        if block in files:
            files[block].append(d)
        else:
            files[block] = [d]

    for block in files:
        files[block] = sorted(files[block], key=lambda d: int(d.name))

    return files

def make_mp4s(blk_len):
    files = encode(blk_len)

    with tempfile.TemporaryFile() as temp:
        for key in files:
            mp4_f = full_dir / (str(key) + ".mp4")
            mp4_s = small_dir / (str(key) + ".mp4")

            if mp4_f.exists():
                print(f"{mp4_f} exists; skipping...")
                continue

            temp.truncate(0)
            for d in files[key]:
                temp.write(f"file '{d}/image.png'\nduration 1.0\n")

            # -vf scale=(480*iw/ih+2):480 -preset veryslow -crf 30
            cmd = ["ffmpeg", "-v", "error", "-f", "concat", "-safe", "0",
                    "-i", temp, "-c:v", "libaom-av1", "-cpu-used", "8",
                    "-pix_fmt", "yuv420p", "-vf", "crop=iw:ih-1", mp4_f]
            subprocess.run(cmd)

            cmd = ["ffmpeg", "-v", "error", "-f", "concat", "-safe", "0",
                    "-i", temp, "-c:v", "libaom-av1", "-cpu-used", "8",
                    "-preset", "veryslow", "-crf", "30",
                    "-pix_fmt", "yuv420p", "-vf", "crop=iw:ih-1,scale=(480*iw/ih+2):480", mp4_s]
            subprocess.run(cmd)

            print(f"made {str(key) + '.mp4'}")

def main():
    blk_len = 300   # 300s = 5m
    make_mp4s(blk_len)

if __name__ == "__main__":
    main()