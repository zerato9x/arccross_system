"""One-off helper to measure sprite regions in the revamped HUD atlases."""
import sys
import numpy as np
from PIL import Image

def clusters(path, min_size=4, pad_gap=2):
    img = Image.open(path).convert("RGBA")
    a = np.array(img)[:, :, 3] > 0
    h, w = a.shape
    # simple flood fill via label from scipy-free BFS on downsampled union-find
    visited = np.zeros_like(a, dtype=bool)
    boxes = []
    from collections import deque
    for y in range(h):
        for x in range(w):
            if a[y, x] and not visited[y, x]:
                q = deque([(y, x)])
                visited[y, x] = True
                y0 = y1 = y
                x0 = x1 = x
                count = 0
                while q:
                    cy, cx = q.popleft()
                    count += 1
                    y0 = min(y0, cy); y1 = max(y1, cy)
                    x0 = min(x0, cx); x1 = max(x1, cx)
                    for dy in range(-pad_gap, pad_gap + 1):
                        for dx in range(-pad_gap, pad_gap + 1):
                            ny, nx = cy + dy, cx + dx
                            if 0 <= ny < h and 0 <= nx < w and a[ny, nx] and not visited[ny, nx]:
                                visited[ny, nx] = True
                                q.append((ny, nx))
                if count >= min_size and (y1 - y0) >= min_size and (x1 - x0) >= min_size:
                    boxes.append((x0, y0, x1 - x0 + 1, y1 - y0 + 1))
    boxes.sort(key=lambda b: (b[1] // 16, b[0]))
    return boxes

if __name__ == "__main__":
    path = sys.argv[1]
    min_w = int(sys.argv[2]) if len(sys.argv) > 2 else 8
    for (x, y, w, h) in clusters(path):
        if w >= min_w and h >= min_w:
            print(f"{x},{y},{w},{h}")
