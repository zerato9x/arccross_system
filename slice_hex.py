import sys
import os
try:
    from PIL import Image, ImageDraw
except ImportError:
    print("Pillow is not installed. Please run: pip install Pillow")
    sys.exit(1)

def create_hex_mask(width, height):
    """Creates a pointy-topped hexagonal mask of the given bounding box size."""
    mask = Image.new('L', (width, height), 0)
    draw = ImageDraw.Draw(mask)
    
    # Define points for a pointy-topped hexagon
    # Top point
    p1 = (width / 2, 0)
    # Top right
    p2 = (width, height / 4)
    # Bottom right
    p3 = (width, height * 3 / 4)
    # Bottom point
    p4 = (width / 2, height)
    # Bottom left
    p5 = (0, height * 3 / 4)
    # Top left
    p6 = (0, height / 4)
    
    draw.polygon([p1, p2, p3, p4, p5, p6], fill=255)
    return mask

def slice_hex_grid(image_path, tile_width=256, tile_height=256):
    try:
        img = Image.open(image_path).convert("RGBA")
    except Exception as e:
        print(f"Error opening image: {e}")
        return

    img_width, img_height = img.size
    print(f"Image size: {img_width}x{img_height}")
    
    # Hex grid dimensions (pointy-topped)
    # Horizontal spacing between columns
    col_spacing = tile_width
    # Vertical spacing between rows
    row_spacing = tile_height * 0.75
    
    cols = int((img_width + (tile_width / 2)) // tile_width)
    rows = int((img_height - tile_height * 0.25) // row_spacing) + 1
    
    print(f"Calculated grid size: {cols} columns, {rows} rows")
    
    # Create output directory
    base_name = os.path.splitext(os.path.basename(image_path))[0]
    out_dir = f"{base_name}_hex_slices"
    os.makedirs(out_dir, exist_ok=True)
    
    hex_mask = create_hex_mask(tile_width, tile_height)
    
    count = 0
    for row in range(rows):
        for col in range(cols):
            # Calculate offset for staggered grid
            offset_x = (tile_width / 2) if (row % 2 != 0) else 0
            
            x = int(col * col_spacing + offset_x)
            y = int(row * row_spacing)
            
            # Skip if the bounding box goes completely outside the image
            # We still want partial tiles if they overlap the image
            if x >= img_width or y >= img_height:
                continue
                
            # Crop the bounding box
            box = (x, y, x + tile_width, y + tile_height)
            tile = img.crop(box)
            
            # Create a transparent background image
            hex_tile = Image.new("RGBA", (tile_width, tile_height), (0, 0, 0, 0))
            
            # Paste the cropped tile using the hex mask
            hex_tile.paste(tile, (0, 0), mask=hex_mask)
            
            # Check if the tile is completely empty to skip
            if not hex_tile.getbbox():
                continue
            
            out_path = os.path.join(out_dir, f"{base_name}_q{col}_r{row}.png")
            hex_tile.save(out_path)
            count += 1
            
    print(f"Successfully saved {count} hexagonal tiles into '{out_dir}'.")

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: python slice_hex.py <path_to_image> [tile_width] [tile_height]")
        sys.exit(1)
        
    img_path = sys.argv[1]
    w = int(sys.argv[2]) if len(sys.argv) > 2 else 256
    h = int(sys.argv[3]) if len(sys.argv) > 3 else 256
    
    slice_hex_grid(img_path, w, h)
