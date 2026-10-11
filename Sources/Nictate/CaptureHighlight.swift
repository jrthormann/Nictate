// Nictate: a macOS menu bar app that copies text from anywhere on your screen.
// Copyright (c) 2026 jrthormann. MIT License, see LICENSE.

/// How a capture row in History is drawn. The keyboard-selected row takes the accent colour, and a row under the pointer
/// gets only a light tint, so the two are never mistaken for each other.
enum CaptureHighlight: Equatable {
    case selected, hovered, none
}

/// The highlight of one capture row. The keyboard selection wins over the pointer, so there is one accented row at most.
func captureHighlight(selected: Bool, hovered: Bool) -> CaptureHighlight {
    selected ? .selected : (hovered ? .hovered : .none)
}
