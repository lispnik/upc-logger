#!/usr/bin/env python3
"""test-sheet.py -- a PDF of UPC-A barcodes to scan while testing the app.

    tools/test-sheet.py                    # upc-test-codes.pdf and .csv here
    tools/test-sheet.py sheet.pdf key.csv

40 distinct codes plus 6 repeats, 10 to a US Letter page, numbered, each
repeat labelled with the number of the code it repeats and placed on a
different page from it.  The CSV beside it is the answer key: index, code,
repeat_of.  Open the PDF on a Mac and scan it off the screen with the phone.

The PDF is written by hand, so no libraries are needed.  The codes come
from a fixed seed, so every run makes the same sheet.
"""
import random
import sys

L = ["0001101", "0011001", "0010011", "0111101", "0100011",
     "0110001", "0101111", "0111011", "0110111", "0001011"]
R = ["".join("1" if b == "0" else "0" for b in code) for code in L]


def check_digit(digits11):
    odd = sum(int(d) for d in digits11[0::2])
    even = sum(int(d) for d in digits11[1::2])
    return str((10 - (odd * 3 + even) % 10) % 10)


def modules(code):
    """The 95 modules of a UPC-A, as a string of 0/1, and which are guards."""
    s = "101" + "".join(L[int(d)] for d in code[:6]) + "01010" \
        + "".join(R[int(d)] for d in code[6:]) + "101"
    assert len(s) == 95
    guard = set(range(0, 3)) | set(range(45, 50)) | set(range(92, 95))
    return s, guard


def barcode_ops(code, x0, y0, module=1.6, height=62.0, guard_extra=8.0):
    """PDF drawing operators for one barcode with its bottom-left at (x0, y0)."""
    s, guard = modules(code)
    ops = []
    i = 0
    while i < 95:
        if s[i] == "1":
            j = i
            while j < 95 and s[j] == "1":
                j += 1
            long_bar = any(k in guard for k in range(i, j))
            bottom = y0 - (guard_extra if long_bar else 0)
            h = height + (guard_extra if long_bar else 0)
            ops.append(f"{x0 + i * module:.2f} {bottom:.2f} {(j - i) * module:.2f} {h:.2f} re f")
            i = j
        else:
            i += 1
    return ops


def text_op(x, y, size, text, font="F1"):
    text = text.replace("\\", "\\\\").replace("(", "\\(").replace(")", "\\)")
    return f"BT /{font} {size} Tf {x:.2f} {y:.2f} Td ({text}) Tj ET"


def build(path, csv_path, seed=20260928):
    rng = random.Random(seed)
    distinct = []
    while len(distinct) < 40:
        body = "0" + "".join(rng.choice("0123456789") for _ in range(10))
        code = body + check_digit(body)
        if code not in distinct:
            distinct.append(code)

    # Six repeats, each placed at least a page away from its original.
    items = [(c, None) for c in distinct]
    for original in (2, 7, 13, 21, 28, 33):
        items.append((distinct[original], original))
    # Interleave: put repeats at fixed later positions rather than all at the end.
    order = items[:40]
    for (code, orig), pos in zip(items[40:], (14, 19, 27, 35, 42, 45)):
        order.insert(min(pos, len(order)), (code, orig))

    # Number every entry, and point each repeat at its original's number.
    first_index = {}
    entries = []
    for n, (code, _) in enumerate(order, start=1):
        repeat_of = first_index.get(code)
        if repeat_of is None:
            first_index[code] = n
        entries.append((n, code, repeat_of))

    page_w, page_h = 612, 792
    per_page = 10
    pages = [entries[i:i + per_page] for i in range(0, len(entries), per_page)]
    streams = []
    for p, page in enumerate(pages, start=1):
        ops = [text_op(40, 755, 14, f"UPC Logger test codes - page {p} of {len(pages)}", "F2"),
               text_op(40, 738, 9, f"{len(entries)} barcodes: {len(distinct)} distinct UPC-A codes, "
                                    f"{len(entries) - len(distinct)} repeats (marked). Seed {seed}.")]
        for k, (n, code, repeat_of) in enumerate(page):
            col, row = k % 2, k // 2
            x = 60 + col * 280
            y = 620 - row * 140
            ops += barcode_ops(code, x, y)
            human = f"{code[0]}  {code[1:6]}  {code[6:11]}  {code[11]}"
            ops.append(text_op(x + 14, y - 22, 12, human, "F3"))
            label = f"#{n}" + (f"   REPEAT of #{repeat_of}" if repeat_of else "")
            ops.append(text_op(x, y + 72, 10, label, "F2" if repeat_of else "F1"))
        streams.append("\n".join(ops).encode("latin-1"))

    # Objects: 1 catalog, 2 pages, 3-5 fonts, then (page, content) pairs.
    objects = {}
    objects[3] = b"<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>"
    objects[4] = b"<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica-Bold >>"
    objects[5] = b"<< /Type /Font /Subtype /Type1 /BaseFont /Courier >>"
    kids = []
    next_id = 6
    for stream in streams:
        page_id, content_id = next_id, next_id + 1
        next_id += 2
        kids.append(page_id)
        objects[page_id] = (f"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 {page_w} {page_h}] "
                            f"/Resources << /Font << /F1 3 0 R /F2 4 0 R /F3 5 0 R >> >> "
                            f"/Contents {content_id} 0 R >>").encode()
        objects[content_id] = (f"<< /Length {len(stream)} >>\nstream\n".encode()
                               + stream + b"\nendstream")
    objects[1] = b"<< /Type /Catalog /Pages 2 0 R >>"
    objects[2] = (f"<< /Type /Pages /Kids [{' '.join(f'{k} 0 R' for k in kids)}] "
                  f"/Count {len(kids)} >>").encode()

    out = bytearray(b"%PDF-1.4\n%\xe2\xe3\xcf\xd3\n")
    offsets = {}
    for oid in sorted(objects):
        offsets[oid] = len(out)
        out += f"{oid} 0 obj\n".encode() + objects[oid] + b"\nendobj\n"
    xref = len(out)
    count = max(objects) + 1
    out += f"xref\n0 {count}\n0000000000 65535 f \n".encode()
    for oid in range(1, count):
        out += f"{offsets[oid]:010d} 00000 n \n".encode()
    out += f"trailer\n<< /Size {count} /Root 1 0 R >>\nstartxref\n{xref}\n%%EOF\n".encode()
    with open(path, "wb") as f:
        f.write(out)

    with open(csv_path, "w") as f:
        f.write("index,code,repeat_of\n")
        for n, code, repeat_of in entries:
            f.write(f"{n},{code},{repeat_of or ''}\n")
    return entries


if __name__ == "__main__":
    pdf_path = sys.argv[1] if len(sys.argv) > 1 else "upc-test-codes.pdf"
    csv_path = sys.argv[2] if len(sys.argv) > 2 else "upc-test-codes.csv"
    entries = build(pdf_path, csv_path)
    print(f"{len(entries)} barcodes, {len(set(c for _, c, _ in entries))} distinct")
    for n, code, repeat_of in entries:
        if repeat_of:
            print(f"  #{n} repeats #{repeat_of} ({code})")
