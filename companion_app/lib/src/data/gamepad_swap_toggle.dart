/// Controller elements that may be mapped to toggle notification **Swap** mode.
///
/// Excludes face buttons and stick used by Swap mouse mode (A/B/X + left stick).
const Set<String> kSwapToggleExcludedElementIds = {
  'buttonA', // Cross — left click in Swap
  'buttonB', // Circle — right click in Swap
  'buttonX', // Square — drag in Swap
  'leftStickUp',
  'leftStickDown',
  'leftStickLeft',
  'leftStickRight',
};

const String kSwapToggleTargetAction = 'toggleSwap';
const String kSwapToggleTargetLabel = 'Swap mode (toggle)';

bool canMapSwapToggleTo(String elementId) =>
    !kSwapToggleExcludedElementIds.contains(elementId);
