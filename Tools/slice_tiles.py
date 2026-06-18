import sys
import os
try:
    from PIL import Image
except ImportError:
    print("Pillow is not installed. Please run: pip install Pillow")
    sys.exit(1)

def slice_spritesheet(image_path, tile_width=256, tile_height=256):
    try:
        img = Image.open(image_path)
    except Exception as e:
        print(f"Error opening image: {e}")
        return

    img_width, img_height = img.size
    print(f"Image size: {img_width}x{img_height}")
    
    # Calculate rows and columns
    cols = img_width // tile_width
    rows = img_height // tile_height
    
    if cols == 0 or rows == 0:
        print(f"Image is smaller than the tile size of {tile_width}x{tile_height}")
        return

    print(f"Slicing into {cols} columns and {rows} rows (Total: {cols*rows} tiles)")
    
    # Create output directory
    base_name = os.path.splitext(os.path.basename(image_path))[0]
    out_dir = f"{base_name}_slices"
    os.makedirs(out_dir, exist_ok=True)
    
    count = 0
    for row in range(rows):
        for col in range(cols):
            left = col * tile_width
            top = row * tile_height
            right = left + tile_width
            bottom = top + tile_height
            
            # Crop and save
            tile = img.crop((left, top, right, bottom))
            
            # Optional: Check if tile is completely empty/transparent to skip it
            # if not tile.getbbox():
            #     continue
            
            out_path = os.path.join(out_dir, f"{base_name}_{col}_{row}.png")
            tile.save(out_path)
            count += 1
            
    print(f"Successfully saved {count} tiles into the '{out_dir}' directory.")

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: python slice_tiles.py <path_to_image> [tile_width] [tile_height]")
        print("Example: python slice_tiles.py spritesheet.png 256 256")
        sys.exit(1)
        
    img_path = sys.argv[1]
    w = int(sys.argv[2]) if len(sys.argv) > 2 else 256
    h = int(sys.argv[3]) if len(sys.argv) > 3 else 256
    
    slice_spritesheet(img_path, w, h)
