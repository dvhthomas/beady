---
title: Themes, text size and languages
linkTitle: Themes and languages
weight: 70
description: Choosing a theme, high contrast, larger text, and the languages Beady speaks.
---

## Themes

Press {{< k "⌘T" >}} to open the theme picker.

{{< shot name="themes" alt="The theme picker, with System, Light and Dark at the top and a list of themes beneath: Dracula, One Dark, Nord, High Contrast Dark, then Solarized Light, GitHub Light and One Light." caption="The picker. Arrow up and down and the whole app repaints as you go." >}}

- Choose **System**, **Light** or **Dark** for the appearance, and a theme for each side.
  Beady uses the dark choice when the appearance is dark and the light choice when it's
  light.
- Dark themes: **Dracula**, **One Dark**, **Nord**. Light themes: **Solarized Light**,
  **GitHub Light**, **One Light**.
- Arrow up and down to try themes on. **Apply** keeps the one you stopped on; **Cancel** or
  {{< k "Esc" >}} puts back what you had.

A theme paints the whole window, sidebar and title bar included. If you'd rather keep macOS's
translucent sidebar, set **Sidebar style** to *Translucent* in Settings ({{< k "⌘," >}}).

{{< shot name="ready-light" crop="640" alt="The Ready view in a light theme." caption="The same view in a light theme." >}}

## High contrast

There's a high-contrast theme on each side. Turn on macOS's **Increase Contrast** setting
and Beady switches to it by itself.

Every theme's contrast is checked by tests: body text meets WCAG AA (4.5:1), status and
priority colours meet 3:1, and the high-contrast themes meet AAA (7:1).

## Text size

Text scales from Small to Extra Large. Change it from {{< k "⌘P" >}} (type `text size`) or
in Settings.

## Languages

Beady speaks English, German, Spanish, French, Japanese, Korean and Brazilian Portuguese. It
follows your Mac's language. To choose one for Beady alone, use **Settings → Language**
({{< k "⌘," >}}); the change takes effect the next time Beady launches.

If a translation could be better, each one is a single file in the repository, and
[the localisation notes](https://github.com/dvhthomas/beady/blob/master/docs/LOCALIZATION.md)
say how to change it.
