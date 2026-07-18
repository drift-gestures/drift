# Custom gestures

Custom gestures turn a trackpad gesture into an action, including an ordered sequence of keyboard shortcuts. This is useful for automating a short command chain—for example, `⌘ Space` → `D` → `Space` → `Return`.

Return to the [user guide](README.md).

## Create a keyboard-shortcut sequence

1. From Drift's menu-bar menu, open **Settings**, then select **Custom Gestures**.
2. Choose **Add Basic Gesture…** or **Add Advanced Gesture…**. Configure the gesture itself; advanced gestures need at least three recorded examples before they can be saved.
3. In **Action**, choose **Keyboard Shortcut**.
4. Under **Shortcut Steps**, click the first step and press the shortcut you want Drift to send. Each recorder captures one key press, including modifier keys held with it; `Return` and `Escape` can also be steps.
5. Click **Add Keyboard Action Step** for each later shortcut, then record it. A sequence supports one through seven steps.
6. For two or more steps, enter an **Interval (ms)** to choose the pause between each pair of steps. New multi-step sequences use 200 ms. Enter a whole number of milliseconds; negative values are treated as 0.
7. Use **Move Up**, **Move Down**, and **Remove** beside a step to correct its order. Drift always keeps at least one step.
8. Click **Save**.

When the gesture is recognized, Drift completes each shortcut before waiting the selected interval and sending the next one. It does not add a wait after the final step.

## Basic and advanced gestures

Basic gestures are available normally. Advanced gestures are recognized only while you hold the **Advanced activation** binding at the top of the Custom Gestures settings page; basic gestures are paused during that time. Set or change that binding by clicking it and holding the modifiers you want, then releasing them. If you release the activation modifiers while a touch is still down, that contact becomes stale: Drift runs neither advanced nor basic gestures until all fingers lift. Drift resets at that lift, and the next touch uses normal (basic) mode unless you hold the activation binding again.

You can limit either kind of gesture to selected applications in its **Scope** section. Leave it at **All Apps** to run everywhere.

## Existing keyboard actions

Keyboard actions saved before shortcut sequences were added remain one-step actions. Edit one in the same **Shortcut Steps** section and use **Add Keyboard Action Step** when you want to extend it into a sequence.

## If a shortcut does not run

Confirm that Input Monitoring and Accessibility are enabled for Drift, then return to **Settings → General** and choose **Retry** if Input Suppression is disabled. Also check that the gesture's scope includes the currently focused app, if it has a scope.

Some shortcut sequences depend on the target app being ready for the next key press. Increase **Interval** when an app does not reliably accept a later step.
