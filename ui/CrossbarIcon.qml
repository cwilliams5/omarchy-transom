import QtQuick
import QtQuick.Shapes

// The Transom mark (branding/crossbar): a window whose bottom rail is the
// taskbar. Drawn here rather than from an image, so it stays sharp at bar
// size and takes the theme's colors. Geometry is the logo's 64-unit grid.
//
// barShown false leaves the rail out (the taskbar is hidden): at bar size
// that's the clearest difference (an outlined rail looked filled). The rail
// still counts toward the shape's bounds, so the icon doesn't move or
// resize on the bar when the state changes.
Item {
  id: root

  property real size: 64
  property color color: "white"
  property bool barShown: true
  // The logo's frame is 4 units. At bar size (about 14 px) that's under a
  // pixel, so the bar asks for a heavier one.
  property real stroke: 4
  readonly property real unit: size / 64

  width: size
  height: size
  implicitWidth: size
  implicitHeight: size

  Shape {
    width: 64
    height: 64
    scale: root.unit
    transformOrigin: Item.TopLeft
    preferredRendererType: Shape.CurveRenderer

    // The window frame.
    ShapePath {
      strokeColor: root.color
      strokeWidth: root.stroke
      fillColor: "transparent"
      joinStyle: ShapePath.RoundJoin
      PathSvg { path: "M 15 8 H 49 A 7 7 0 0 1 56 15 V 49 A 7 7 0 0 1 49 56 H 15 A 7 7 0 0 1 8 49 V 15 A 7 7 0 0 1 15 8 Z" }
    }

    // The glazing bars.
    ShapePath {
      strokeColor: root.color
      strokeWidth: root.stroke * 0.875
      fillColor: "transparent"
      PathSvg { path: "M 32 8 V 42 M 8 25 H 56" }
    }

    // The rail: the taskbar.
    ShapePath {
      strokeColor: "transparent"
      fillColor: root.barShown ? root.color : "transparent"
      PathSvg { path: "M 6 41 H 58 V 49 A 9 9 0 0 1 49 58 H 15 A 9 9 0 0 1 6 49 Z" }
    }
  }
}
