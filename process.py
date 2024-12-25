import subprocess
import time
import datetime
import os
from pathlib import Path


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

def encode():
    count = 0

    # FIXME code is still defining start of day relative to localtime instead of UTC apparently
    make_partial_today = True # DBG
    datadir = Path.home() / "ss"
    start_files = []

    dirs = sorted(os.listdir(datadir))
    dirs2 = []
    for i in range(len(dirs)):
        fpath = datadir / dirs[i]
        if not os.path.isdir(fpath):
            continue
        dirs2.append(dirs[i])
    dirs = dirs2

    for i in range(len(dirs)-1):
        fpath = datadir / dirs[i]
        fpath_next = datadir / dirs[i+1]

        date = dir_to_date(fpath)
        date_next = dir_to_date(fpath_next)

        if i == 0:
            start_files.append(fpath)
        
        if not same_date(date, date_next):
            start_files.append(fpath_next)

        ocr(fpath)
        count += 1
        if count > 5:
            break

    # while i < len(dirs):
    #     fpath = datadir / dirs[i]
    #     i += 1

    #     if not os.path.isdir(fpath):
    #         continue

    #     date = dir_to_date(fpath)
    #     if same_date(date, utc_today()):
    #         if not make_partial_today:
    #             break
    #         # TODO should instead just wait until the next day instead of exiting loop

    #     mp4 = datadir / (date.replace(hour=0, minute=0, second=0).strftime("%s") + ".mp4")
    #     if mp4.exists():
    #         if not same_date(date, utc_today()) or not make_partial_today:
    #             continue

    #     files = [fpath / "image.png"]
    #     while i < len(dirs):
    #         fpath2 = datadir / dirs[i]
    #         i += 1

    #         if not os.path.isdir(fpath2):
    #             continue

    #         date2 = dir_to_date(fpath2)
    #         if not same_date(date, date2):
    #             break

    #         files.append(fpath2 / "image.png")

    #     with open(datadir / "list.txt", 'w') as f:
    #         for file in files:
    #             f.write(f"file '{file}'\nduration 0.05\n")

    #     # -vf scale=(480*iw/ih+2):480 -preset slow -crf 28
    #     cmd = ["ffmpeg", "-y", "-hide_banner", "-f", "concat", "-safe", "0",
    #            "-i", str(datadir / "list.txt"), "-c:v", "libx265",
    #            "-pix_fmt", "yuv420p", "-vf", "crop=iw:ih-1", str(mp4)]
    #     subprocess.run(cmd)


def main():
    encode()


if __name__ == "__main__":
    main()