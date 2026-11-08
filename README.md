# PixelCrop

An image cropping and comparison tool exclusively for Apple Silicon on macOS. **For personal, local use only**; intended for macOS 26 Tahoe.

## Design Principles

1. **Extremely low memory usage**: Uses `CGImageSource` for on-demand downsampling; **never loads the full-resolution image into memory**. A 100MP image occupies only the memory equivalent to its displayed dimensions within the UI.
2. **macOS design guidelines**: SwiftUI + Liquid Glass-style controls that automatically adapt to the system’s light and dark modes.
3. **Pixel ↔ Aspect Ratio Synchronisation**: Enter 0.5 MP to automatically calculate specific width and height values for aspect ratios such as 9:21, 9:16, 2:3, 3:4 and 1:1; dragging the selection box displays the current MP value in real time (rounded to one decimal place).
4. **Convenient Import and Export**: Convert between JPEG, PNG, HEIC and WebP; adjustable quality; **all metadata is discarded**.
5. **Side-by-Side Comparison**: Hide/show mode (hold down the button) + drag-to-display mode (horizontal/vertical divider lines); the two images may have different dimensions or aspect ratios and can be scaled independently by dragging.

## System Requirements

- **macOS 26 Tahoe** or later
- **Apple Silicon** (any of M1/M2/M3/M4)
- Xcode 26 command-line tools: `xcode-select --install`

## Building

```bash
cd PixelCrop
./build.sh release          # Recommended: Release build – small file size, fast execution
# Or
./build.sh                  # Debug build

open build/PixelCrop.app    # Run
```

Optional: Drag into `/Applications` for long-term use:

```bash
mv build/PixelCrop.app /Applications/
```

## Usage

### Import
- Menu: **File → Open Image…** (⌘O)
- Drag files directly onto any part of the window
- Supports JPEG / PNG / HEIC / WebP

### Cropping
1. Enter the target MP (e.g. `0.5`) in the ‘Target Pixels (MP)’ field on the right, then click ‘Apply’ or press Enter → the selection box will scale whilst maintaining the current aspect ratio
2. Select 9:21 / 9:16 / 2:3 / 3:4 / 1:1 / 4:3 / 3:2 / 16:9 / 21:9 from the ‘Aspect Ratio Presets’ grid → locks to that aspect ratio (whilst maintaining the current MP)
3. Drag any of the 8 handles on the selection box to resize it; drag inside the selection box to move it as a whole
4. The current MP, pixel dimensions and the closest preset aspect ratio are displayed in real time in the bottom-right corner
5. Click ‘Switch to Free Aspect Ratio’ to unlock

### Comparison
1. Switch the mode at the top to ‘Comparison’
2. Select ‘Left Image’ and ‘Right Image’ at the top
3. Select a comparison method:
   - **Hide/Show**: The right-hand image is displayed on top by default; hold down the bottom button → hide the top layer to display the bottom layer; release to restore
   - **Drag to Reveal**: A horizontal or vertical divider line; drag the circular handle to change the display ratio
4. Each image can be dragged and positioned independently, and zoomed using two fingers (the sizes/ratios of the two images do not need to match)
5. Tap ‘Reset Position’ at the bottom to restore to the initial state

### Export
1. Tap the ‘Export…’ button on the right
2. Select a format (JPEG / PNG / HEIC / WebP)
3. Adjust the quality slider (PNG does not have a quality setting)
4. Select a preset (High / Medium-High / Medium / Low)
5. ‘Select location and export…’ → Standard NSSavePanel
6. The output filename automatically includes the ‘MP’ tag, e.g. `photo-0.5mp.jpeg`

### Undo / Redo
- ⌘Z Undo
- ⇧⌘Z Redo
- Up to 10 steps; the history is cleared when the window is closed

## Keyboard shortcuts

| Shortcut | Function   |
| -------- | ---------- |
| ⌘O       | Open image |
| ⌘Z       | Undo       |
| ⇧⌘Z      | Redo       |

## Project Structure

```
PixelCrop/
├── Package.swift                  SwiftPM 6.1, targeting macOS 26
├── build.sh                       One-click compilation + assembly of .app bundle
├── README.md                      This document
├── Resources/
│   └── Info.plist                 Bundle configuration (including LSMinimumSystemVersion 26.0)
└── Sources/PixelCrop/
    ├── PixelCropApp.swift         App entry point, menu commands
    ├── Models/
    │   ├── AppState.swift         @Observable global state (@MainActor)
    │   ├── CropRatio.swift        9 preset aspect ratios
    │   ├── CropRect.swift         Normalised cropping rectangle
    │   └── UndoStack.swift        Lightweight undo stack (independent per tab, 10 steps)
    ├── Services/
    │   ├── ImageLoader.swift      CGImageSource on-demand downsampling (memory-optimised control)
    │   └── ImageExporter.swift    ImageIO stream-based export, discarding all metadata
    ├── Utils/
    │   ├── PixelCalculator.swift  MP ↔ scale bidirectional conversion
    │   └── ImageFormat.swift      JPEG/PNG/HEIC/WebP definitions
    └── Views/
        ├── RootView.swift         Root layout + global sheet
        ├── SidebarLayout.swift    Single-window sidebar layout
        ├── TabbedLayout.swift     Tabbed layout
        ├── CanvasArea.swift       Central canvas distribution
        ├── CropCanvas.swift       Crop canvas (NSViewRepresentable drag-and-drop selection box)
        ├── CropInspector.swift     Inspector panel on the right-hand side in crop mode
        ├── ExportSheet.swift      Export sheet
        ├── CompareCanvas.swift    Canvas in comparison mode (hide/show + drag to reveal)
        ├── CompareInspector.swift    Right-hand inspector for comparison mode
        └── ThumbnailView.swift    Thumbnail + full-canvas display view
```



## Notes on Memory Usage

| Operation                             | Memory Increment                                             |
| ------------------------------------- | ------------------------------------------------------------ |
| Open a 50 MP image                    | ~5 MB (CGImageSource descriptor + original image size only)  |
| Display on canvas (1920×1080 view)    | ~16 MB (CGImage downsampled to view dimensions)              |
| Thumbnail list (10 images, 36×36)     | ~0.1 MB                                                      |
| Export cropped result (instantaneous) | Temporary full-pixel decoding; memory released upon export completion |

**Never** occurs:
- ❌ Full-pixel decoding of the original image and keeping it in memory
- ❌ Caching multiple uncompressed bitmaps
- ❌ Holding the original image and multiple cropped previews simultaneously

## Known limitations

- Batch processing not supported (per user request)
- Rotation / flipping / perspective correction not supported (per user request)
- EXIF / histogram / colour picker not displayed (per user request)
- All metadata is forcibly discarded upon export (per user request)
- The undo stack is valid only within the current session; it is cleared upon closing the window (per user request)


