# Zivo UI colour and type tokens

| Role | Hex | Flutter |
| --- | --- | --- |
| Primary black / actions | #000000 | Color(0xFF000000) |
| Background white | #FFFFFF | Color(0xFFFFFFFF) |
| Surface grey | #F6F6F6 | Color(0xFFF6F6F6) |
| Card grey | #F3F3F3 | Color(0xFFF3F3F3) |
| Borders | #E2E2E2 | Color(0xFFE2E2E2) |
| Secondary text | #545454 | Color(0xFF545454) |
| Muted text | #686868 | Color(0xFF686868) |
| Reference green / decorative accents | #06C167 | Color(0xFF06C167) |
| Readable semantic green | #087F5B | Color(0xFF087F5B) |
| Glass white, 85% opacity | rgba(255,255,255,0.85) | Color(0xD9FFFFFF) |

Black and green match the supplied screenshot. Supporting neutrals are the app's design choices, not a claim of official Uber tokens.

Use black actions, white primary surfaces and grey grouping. Keep bright green for small decorative accents; use the darker semantic green for green text on white. Primary text remains black.

Font: bundled Inter. Display 32–40px / 700; headings 20–26px / 600–700; body 14–16px / 400; action labels 16px / 600. Financial display styles use tabular figures. This is an Uber-inspired hierarchy using Inter, not the proprietary Uber Move family.

Components: shared vector service icons, 12–16px card corners, 22px navigation selections, 30px glass dock corners. Mobile glass navigation is retained; desktop uses a persistent sidebar at 1100px and above.
