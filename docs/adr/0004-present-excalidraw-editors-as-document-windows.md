# Present Excalidraw editors as document windows

Excalidraw editors use a dedicated normal macOS document-window subsystem rather than HUD presentation because drawings are persistent, independently focusable workspaces that must support multiple windows, resizing, minimization, full screen, Dock presence, and standard close semantics. The transient Excalidraw launcher remains a HUD and hands drawing requests to the window subsystem, which owns at most one live window per drawing.
