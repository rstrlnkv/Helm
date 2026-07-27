# Measuring, instead of judging by eye

`measure-disk-bar.swift` sizes the Disk result screen with the real font
metrics — the same fonts the views use — and prints what each piece needs
against the window sizes the app can actually be.

```bash
swiftc -O -o /tmp/measure Scripts/layout/measure-disk-bar.swift && /tmp/measure
```

The numbers it prints are the ones `DiskLayout` turns into thresholds and
`DiskLayoutTests` pins. Run it after adding anything to the breadcrumb bar or
changing a font: the bar overflowed at *every* window size for a while, at the
default one by 94 pt, and nothing said so because nobody had measured.
