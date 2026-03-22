import SwiftUI

struct PlusButtonView: View {
    let nodeID: UUID
    let direction: DragDirection
    @ObservedObject var viewModel: DominoViewModel

    @State private var isDragging = false
    @State private var isHovering = false

    private let size: CGFloat = 18

    var body: some View {
        Circle()
            .fill(isHovering ? Color.accentColor : Color.primary.opacity(0.15))
            .frame(width: size, height: size)
            .overlay(
                Image(systemName: "plus")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(isHovering ? .white : .primary.opacity(0.5))
            )
            .scaleEffect(isHovering ? 1.15 : 1.0)
            .animation(.easeOut(duration: 0.15), value: isHovering)
            .gesture(
                DragGesture(minimumDistance: 5, coordinateSpace: .named("canvas"))
                    .onChanged { value in
                        isDragging = true
                        viewModel.edgeDrag = EdgeDragState(
                            sourceNodeID: nodeID,
                            direction: direction,
                            currentPoint: value.location
                        )
                        viewModel.dropTargetNodeID = viewModel.nodeAt(point: value.location, excluding: nodeID)
                    }
                    .onEnded { value in
                        isDragging = false
                        viewModel.edgeDrag = nil
                        viewModel.dropTargetNodeID = nil
                        // If dropped on an existing node, connect/disconnect
                        if !viewModel.handleEdgeDrop(sourceID: nodeID, dropPoint: value.location, direction: direction) {
                            // Otherwise create a new child at drop point
                            viewModel.addChildNode(
                                parentID: nodeID,
                                direction: direction,
                                at: value.location
                            )
                        }
                    }
            )
            .simultaneousGesture(
                TapGesture()
                    .onEnded {
                        if !isDragging {
                            viewModel.addChildNode(parentID: nodeID, direction: direction)
                        }
                    }
            )
            .onHover { hovering in
                isHovering = hovering
                if hovering {
                    NSCursor.pointingHand.push()
                } else {
                    NSCursor.pop()
                }
            }
    }
}

extension View {
    func cursor(_ cursor: NSCursor) -> some View {
        onHover { inside in
            if inside {
                cursor.push()
            } else {
                NSCursor.pop()
            }
        }
    }
}
