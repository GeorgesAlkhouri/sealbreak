# Dynamic Type regression checks

These are manual acceptance checks, not a record of completed Simulator tests.
Use a disposable test server and a test share, never production recovery material.
Record the commit, device, operating-system version, text-size category, and result.

## Size and device matrix

Check `.large`, `.xxxLarge`, `.accessibility1`, `.accessibility3`, and
`.accessibility5`. Include the smallest supported iPhone Simulator and a larger
model. Repeat the largest accessibility size in landscape and with the keyboard
visible. Also change the preferred text size while each screen is already open.
Return to `.large` and verify that the compact layout returns.

## Acceptance criteria

All visible text must respond to the preference. Read-only text, status messages,
recovery guidance, and action labels must remain fully readable without ellipses
or font shrinking. Vertical scrolling and multiline labels are expected at large
sizes. Single-line text and secure input fields may scroll horizontally while
editing; their text must fit vertically, and the share must remain concealed.

The Papercut background, shield, status ring, and decorative icons intentionally
retain their sizes. Step-number badges scale to accommodate their numeric text.
Do not cap the supported Dynamic Type range to make a screenshot fit.

## Welcome

Check the title, description, compatibility copy, setup action, and a long notice.
The OpenBao/Vault compatibility row must change to a vertical arrangement when
there is insufficient width. Exercise the reset-required state and its long
`Reset local Sealbreak data` label, including the busy state and confirmation.

## Setup navigation

The header, Cancel action, and both progress steps must remain reachable. When a
horizontal arrangement no longer fits, the header and progress indicator must
reflow instead of squeezing text. Use the single outer scroll view to reach all
content, including in landscape with the keyboard open.

Scroll down on the instance step and continue to the share step. The new step
must start at the top. Go back and verify the name and address are preserved.
Cancel with and without a draft; verify the discard confirmation and return to
Welcome still behave as before. VoiceOver should announce each step's number,
name, and current/completed state.

## Instance setup

Check both field labels, placeholder and entered text, connection-check activity,
certificate/product/DNSSEC results, and a long error message. Use a long server
name and hostname. Verify the Check connection, Checking, and Continue states.
Text fields and buttons must grow vertically without hiding their contents.

## Share setup

Check a long target name and hostname, both security notes, the secure input,
Protect with Face ID, Protecting, and error feedback. Target text and recovery
instructions must wrap rather than truncate. Invalid input must still disable
Protect. A cancelled Face ID prompt must keep the current step usable. Verify
backgrounding/screen-capture handling still clears the sensitive draft, and that
successful saving still follows the existing flow.

## Home

Check unknown, checking, sealed, unsealing, and unsealed states, including progress
and errors. Use long server metadata. The full status title must remain readable,
including UNSEALED and UNSEALING; it may wrap but must not be shrunk to a fixed
single line. The menu and primary action must remain reachable. At default size,
check card spacing and ensure the layout does not gain unnecessary scroll height.

## Existing system-form screens

Open Server details and Replace local share at `.accessibility5`. Check long
values, result messages, the recovery toggle, secure input, save action, and
navigation buttons. These views already use system forms and text styles; they
remain part of the acceptance pass even though this change does not rewrite them.

## Validation boundaries

`swiftc -frontend -parse` checks syntax only. The existing macOS workflow compiles
the complete iOS app and runs the core tests. The core package excludes these
views, so a green core test or coverage result is not a visual layout test.
The Welcome preview includes `.accessibility5`; previews and the manual matrix
still need to be exercised in Xcode or Simulator before accepting the layout.
