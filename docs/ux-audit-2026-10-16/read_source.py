import sys
from pathlib import Path
for arg in sys.argv[1:]:
    parts=arg.split(":")
    p=Path(parts[0]); start=int(parts[1]) if len(parts)>1 else 1; end=int(parts[2]) if len(parts)>2 else 100000
    print("\nFILE",p)
    for i,line in enumerate(p.read_text().splitlines(),1):
        if start<=i<=end and line.strip() and not line.strip().startswith("//"):
            print(f"{i}: {line}")
