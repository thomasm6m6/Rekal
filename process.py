import subprocess
from datetime import datetime, timezone, timedelta
import os
import sys
from pathlib import Path

import pprint
pp = pprint.PrettyPrinter(indent=2)

datadir = Path.home() / "ss"

def ocr(fpath):
    cmd = ["ocr", str(fpath / "image.png")]
    result = subprocess.check_output(cmd).decode()
    with open(fpath / "ocr.txt", 'w') as f:
        f.write(result)


def same_date(date1, date2):
    return date1.year == date2.year and date1.month == date2.month and date1.day == date2.day

def dir_to_date(dir):
    dt = datetime.datetime.fromtimestamp(int(dir.name), tz=datetime.UTC)
    return dt

def utc_today():
    dt = datetime.datetime.now(datetime.UTC)
    return dt

def encode(pprint=False):
    files = {}
    for d in datadir.iterdir():
        if not d.is_dir():
            continue
        n = int(d.name)
        # n//86400 % 2 * 86400 == 0 or 86400
        day = (n - n//86400 % 2 * 86400) // 86400
        if day in files:
            files[day].append(d)
        else:
            files[day] = [d]

    for key in files:
        files[key] = sorted(files[key], key=lambda d: int(d.name))

    if pprint:
        pp.pprint(files)
    return files

def make_mp4s():
    files = encode()
    list_txt = str(datadir / "list.txt")
    for key in files:
        mp4 = datadir / (str(key) + ".mp4")
        if mp4.exists():
            print(f"{mp4} exists; skipping...")
            continue

        with open(list_txt, 'w') as f:
            for d in files[key]:
                f.write(f"file '{d}/image.png'\nduration 0.05\n")

        # -vf scale=(480*iw/ih+2):480 -preset slow -crf 28
        cmd = ["ffmpeg", "-y", "-hide_banner", "-f", "concat", "-safe", "0",
               "-i", list_txt, "-c:v", "libx265",
               "-pix_fmt", "yuv420p", "-vf", "crop=iw:ih-1", str(mp4)]
        subprocess.run(cmd)

def main():
    if len(sys.argv) > 1 and sys.argv[1] == 'd':
        encode(pprint=True)
    else:
        make_mp4s()


if __name__ == "__main__":
    main()