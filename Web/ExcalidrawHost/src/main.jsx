import React, { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { createRoot } from "react-dom/client";
import {
  Excalidraw,
  THEME,
  exportToBlob,
  serializeAsJSON
} from "@excalidraw/excalidraw";
import "@excalidraw/excalidraw/index.css";
import "./styles.css";

const THEME_PREFERENCE = Object.freeze({
  SYSTEM: "system",
  LIGHT: THEME.LIGHT,
  DARK: THEME.DARK
});

const postToNative = (message) => {
  window.webkit?.messageHandlers?.drift?.postMessage?.(message);
};

const isSupportedTheme = (theme) => theme === THEME.LIGHT || theme === THEME.DARK;

const isSupportedThemePreference = (themePreference) => {
  return themePreference === THEME_PREFERENCE.SYSTEM || isSupportedTheme(themePreference);
};

const resolveThemePreference = (themePreference, detectedSystemTheme) => {
  return isSupportedTheme(themePreference) ? themePreference : detectedSystemTheme;
};

const systemTheme = () => {
  return window.matchMedia?.("(prefers-color-scheme: dark)").matches
    ? THEME.DARK
    : THEME.LIGHT;
};

const normalizeIncomingDocument = (payload) => {
  const document = payload?.document ?? {};
  return {
    documentID: payload?.documentID ?? "",
    title: payload?.title ?? "Untitled",
    preferredTheme: isSupportedThemePreference(payload?.preferredTheme)
      ? payload.preferredTheme
      : THEME_PREFERENCE.SYSTEM,
    elements: Array.isArray(document.elements) ? document.elements : [],
    appState: document.appState ?? {},
    files: document.files ?? {}
  };
};

const focusEditor = () => {
  window.requestAnimationFrame(() => {
    document.querySelector(".excalidraw-container")?.focus?.({
      preventScroll: true
    });
  });
};

function App() {
  const [excalidrawAPI, setExcalidrawAPI] = useState(null);
  const [documentInfo, setDocumentInfo] = useState(() => normalizeIncomingDocument({}));
  const [detectedSystemTheme, setDetectedSystemTheme] = useState(systemTheme);
  const [documentThemePreference, setDocumentThemePreference] = useState(
    THEME_PREFERENCE.SYSTEM
  );
  const documentIDRef = useRef("");
  const latestSceneRef = useRef(null);
  const saveTimerRef = useRef(null);
  const activeTheme = resolveThemePreference(documentThemePreference, detectedSystemTheme);
  const activeThemeRef = useRef(activeTheme);
  const documentThemePreferenceRef = useRef(documentThemePreference);
  const programmaticThemeRef = useRef(null);
  const themeReadyRef = useRef(false);

  const initialData = useMemo(
    () => ({
      elements: documentInfo.elements,
      appState: {
        ...documentInfo.appState,
        theme: activeTheme,
        collaborators: undefined
      },
      files: documentInfo.files,
      scrollToContent: documentInfo.elements.length > 0
    }),
    [documentInfo.documentID, activeTheme]
  );

  useEffect(() => {
    activeThemeRef.current = activeTheme;
    documentThemePreferenceRef.current = documentThemePreference;
  }, [activeTheme, documentThemePreference]);

  useEffect(() => {
    const query = window.matchMedia?.("(prefers-color-scheme: dark)");
    if (!query) {
      return undefined;
    }

    const updateSystemTheme = () => {
      setDetectedSystemTheme(query.matches ? THEME.DARK : THEME.LIGHT);
    };

    updateSystemTheme();
    if (query.addEventListener) {
      query.addEventListener("change", updateSystemTheme);
    } else {
      query.addListener?.(updateSystemTheme);
    }
    return () => {
      if (query.removeEventListener) {
        query.removeEventListener("change", updateSystemTheme);
      } else {
        query.removeListener?.(updateSystemTheme);
      }
    };
  }, []);

  const applyTheme = useCallback((theme) => {
    if (!excalidrawAPI) {
      return;
    }

    programmaticThemeRef.current = theme;
    excalidrawAPI.updateScene({
      appState: { theme },
      captureUpdate: "NEVER"
    });
    window.requestAnimationFrame(() => {
      if (programmaticThemeRef.current === theme) {
        programmaticThemeRef.current = null;
      }
      themeReadyRef.current = true;
    });
  }, [excalidrawAPI]);

  useEffect(() => {
    applyTheme(activeTheme);
  }, [activeTheme, applyTheme]);

  const postSceneToNative = useCallback((scene, thumbnailDataURL = null) => {
    const documentID = documentIDRef.current;
    if (!scene || !documentID) {
      return;
    }

    postToNative({
      type: "change",
      documentID,
      document: serializeAsJSON(
        scene.elements,
        {
          ...scene.appState,
          theme: activeThemeRef.current
        },
        scene.files,
        "local"
      ),
      thumbnailDataURL,
      themePreference: documentThemePreferenceRef.current,
      thumbnailTheme: activeThemeRef.current
    });
  }, []);

  const sendSceneToNative = useCallback(async () => {
    const scene = latestSceneRef.current;
    if (!scene || !documentIDRef.current) {
      return;
    }

    let thumbnailDataURL = null;
    try {
      const blob = await exportToBlob({
        elements: scene.elements,
        appState: {
          ...scene.appState,
          theme: activeThemeRef.current,
          exportBackground: true
        },
        files: scene.files,
        mimeType: "image/png",
        quality: 0.72
      });
      thumbnailDataURL = await new Promise((resolve) => {
        const reader = new FileReader();
        reader.onloadend = () => resolve(reader.result);
        reader.readAsDataURL(blob);
      });
    } catch {
      thumbnailDataURL = null;
    }

    postSceneToNative(scene, thumbnailDataURL);
  }, [postSceneToNative]);

  const scheduleSave = useCallback(() => {
    if (saveTimerRef.current !== null) {
      return;
    }
    saveTimerRef.current = window.setTimeout(() => {
      saveTimerRef.current = null;
      sendSceneToNative();
    }, 700);
  }, [sendSceneToNative]);

  const onChange = useCallback((elements, appState, files) => {
    const changedTheme = isSupportedTheme(appState.theme) ? appState.theme : null;
    const isProgrammaticThemeChange = changedTheme !== null &&
      programmaticThemeRef.current === changedTheme;

    latestSceneRef.current = { elements, appState, files };
    if (isProgrammaticThemeChange) {
      programmaticThemeRef.current = null;
      if (
        themeReadyRef.current &&
        documentThemePreferenceRef.current === THEME_PREFERENCE.SYSTEM
      ) {
        scheduleSave();
      }
      return;
    }
    if (
      themeReadyRef.current &&
      changedTheme !== null &&
      changedTheme !== activeThemeRef.current
    ) {
      setDocumentThemePreference(changedTheme);
      documentThemePreferenceRef.current = changedTheme;
      activeThemeRef.current = changedTheme;
      scheduleSave();
      return;
    }
    scheduleSave();
  }, [scheduleSave]);

  useEffect(() => {
    window.driftExcalidrawLoad = (payload) => {
      const nextDocument = normalizeIncomingDocument(payload);
      const nextThemePreference = nextDocument.preferredTheme;
      const nextActiveTheme = resolveThemePreference(nextThemePreference, systemTheme());
      const nextAppState = {
        ...nextDocument.appState,
        theme: nextActiveTheme
      };
      documentIDRef.current = nextDocument.documentID;
      setDocumentInfo(nextDocument);
      setDocumentThemePreference(nextThemePreference);
      documentThemePreferenceRef.current = nextThemePreference;
      activeThemeRef.current = nextActiveTheme;
      themeReadyRef.current = false;
      latestSceneRef.current = {
        elements: nextDocument.elements,
        appState: nextAppState,
        files: nextDocument.files
      };
      if (excalidrawAPI) {
        programmaticThemeRef.current = nextActiveTheme;
        excalidrawAPI.updateScene({
          elements: nextDocument.elements,
          appState: nextAppState,
          collaborators: new Map()
        });
        excalidrawAPI.addFiles(Object.values(nextDocument.files));
        excalidrawAPI.history.clear();
        excalidrawAPI.refresh();
      }
      window.requestAnimationFrame(() => {
        if (programmaticThemeRef.current === nextActiveTheme) {
          programmaticThemeRef.current = null;
        }
        themeReadyRef.current = true;
      });
      focusEditor();
    };
    window.driftExcalidrawFocus = focusEditor;
    postToNative({ type: "ready" });
    focusEditor();

    return () => {
      window.clearTimeout(saveTimerRef.current);
      saveTimerRef.current = null;
      postSceneToNative(latestSceneRef.current);
      delete window.driftExcalidrawLoad;
      delete window.driftExcalidrawFocus;
    };
  }, [excalidrawAPI, postSceneToNative]);

  return (
    <Excalidraw
      key={documentInfo.documentID || "empty"}
      initialData={initialData}
      excalidrawAPI={setExcalidrawAPI}
      onChange={onChange}
      autoFocus
      handleKeyboardGlobally
      UIOptions={{
        canvasActions: {
          saveToActiveFile: false,
          loadScene: false,
          export: {
            saveFileToDisk: true
          }
        }
      }}
    />
  );
}

createRoot(document.getElementById("root")).render(<App />);
