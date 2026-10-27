# Product page header — creative record

Drafts made 27 Oct 2026 for Air Today's App Store product page header (iOS 27 / iPadOS 27 and later).
Nothing here has been uploaded to App Store Connect yet.

| File | What it is |
|---|---|
| `header-A.png` | Concept A, "The verdict" (recommended) |
| `header-B.png` | Concept B, "Morning run" (recommended test challenger) |
| `header-C.png` | Concept C, "Six skies" (scored 76, below the 80 bar; not for release as is) |
| `header-previews.jpg` | Each draft at iPad landscape width, and its safe area at iPhone width |
| `tools/header.swift` | Composes the drafts: `swiftc -O header.swift -o header && ./header A <AQIBackgrounds dir> out.png [--guides] [--notext]` |
| `tools/validate.py` | Checks a draft against Apple's spec and measures text contrast (needs Pillow) |
| `tools/previews.py` | Builds the preview sheet (needs Pillow) |

`<AQIBackgrounds dir>` is `AirTodayApp/Assets.xcassets/AQIBackgrounds`. All three drafts use only the app's own background photos and its own type (system font via CoreText), with no device frames.

## Verified requirements (checked 27 Oct 2026)

| Rule | Class | Source |
|---|---|---|
| Header image 21:9, 3840 × 1646 px | Apple requirement | [Creative assets specifications](https://developer.apple.com/help/app-store-connect/reference/app-information/creative-assets-specifications); API spec `i3840x1646a0` (`asc asset-library specs`) |
| PNG. The help page also lists JPEG, but the API spec accepts `image/png` only | Apple requirement (sources conflict; PNG satisfies both) | Same two sources |
| No alpha channel or transparency | Apple requirement | Same; API `alphaAllowed: false` |
| Max file size 524,288,000 bytes | Apple requirement | API spec `maxFileSize` |
| One header per placement (version, custom product page, or PPO treatment) | Apple requirement | API `placementPolicies`, `maxCount: 1` |
| Header video: 21:9 3840 × 1646, 30 or 60 fps, 5–30 s, .mov/.m4v/.mp4, muted by default, loops | Apple requirement | Help page; API `duration PT5S–PT30S` (its short name says `t10~30`, which conflicts with the duration field) |
| Shows on iOS 27 and iPadOS 27 and later | Apple requirement | [Manage your App Store assets](https://developer.apple.com/help/app-store-connect/manage-app-information/manage-your-app-store-assets) |
| Art safe area 1646 × 661 at (1097, 493), centred | Apple template | `creative_assets-templates.sketch` (Apple CDN, modified 28 Aug 2026, sha256 `0f6f6f86…8957`), layer "Header - 3840x1646 / Art Safe Area"; matches an independent measurement at blakecrosley.com |
| No specific pricing, discounts, URLs or © symbols | Apple requirement | [Asset best practices](https://developer.apple.com/app-store/asset-best-practices/); App Review Guideline 2.3.14 |
| No unverifiable claims, Apple recognitions, or other platforms or marketplaces | Apple requirement | Best practices; Guidelines 2.3.10, 2.3.14 |
| Must suit a 4+ age rating | Apple requirement | Best practices; Guideline 2.3.8 |
| You must hold the rights to everything shown | Apple requirement | Guidelines 2.3.9, 5.2.1 |
| "Focus on a single, clear idea"; "design with a first-time visitor in mind"; focal art in the centre | Apple recommendation | Best practices |
| Short phrase that "enhances your visual rather than describes it" | Apple recommendation | Best practices |
| Header and search results can be tested in product page optimisation | Apple requirement (capability) | API `PRODUCT_PAGE_OPTIMIZATIONS` placement policies; [configure test treatments](https://developer.apple.com/help/app-store-connect/create-product-page-optimization-tests/configure-test-treatments) |
| How the 21:9 frame is cropped on each device | Unverified | Apple doesn't document it. Check in App Store Connect's Preview tool |
| Headline of 3–7 words; px per pt of 4.4 (safe area ≈ iPhone width) | Internal heuristic | This record |

## Results

| | A · The verdict | B · Morning run | C · Six skies |
|---|---|---|---|
| Copy | "Great day to be outside" / 24 / "Good · PM2.5" (the app's own hero strings) | "Go out when the air is cleanest" | "Air quality you can see" |
| Score (internal rubric, out of 100) | 87 | 82 | 76 |
| Text ink inside safe area | Yes (margins L197 R198 T45 B30 px) | Yes (L478 R99 T204 B176) | Yes (L89 R90 T277 B247) |
| White text contrast on its background, before the text shadow (mean / brightest 5%) | 5.07 / 3.77 : 1 | 8.41 / 6.04 : 1 | 10.56 / 6.69 : 1 |
| Spec checks (size, PNG, no alpha, sRGB, file size) | Pass | Pass | Pass |

## Open items (must be settled before release)

1. **Image rights.** The six `AQIBackgrounds` photos ship in the app, but carry no author, licence or provenance metadata, and no record of their source exists in the repo. On 27 Oct 2026 the owner confirmed holding the rights to `good.jpg` for App Store marketing, which covers concept A. The other five photos, used by C, are still unconfirmed. B also uses `good.jpg`, but shows an identifiable person.
2. **Device crop: unverified.** Check each draft in App Store Connect › Header and Search Results › Preview, on iPhone and iPad in both orientations.
3. **Timing.** 1.4.0 is in review. Once it's approved, upload to Asset Library and submit as a standalone asset review: `asc asset-library images upload`, then `asc review items add --item-type appAssetLibraryImages`, then `asc review submissions-submit`. Then publish it to the live version's header.

## Decisions and assumptions

- The app is Air Today. The only App Store localisation is en-GB, so one set of English copy covers every storefront.
- A static image, not video. The app's motion is subtle, and a muted loop wouldn't say more than the still.
- Header only, with no dedicated search-results asset. The search card keeps showing the real screenshots, which Apple's own advice ("state the obvious", "showcase the firsthand experience") favours. A universal 16:9 asset would need a different layout, because its safe area sits 334 px above centre.
- No device frames, which keeps the marketing-guideline bezel rules out of scope. No App Store badge, and no logo: the icon and name sit right below the header.
- A and B enlarge one 1536 × 2752 photo about 2.5×. A's crop is smooth sky, so it shows no texture. B is softened on purpose, with a Gaussian σ of 4 px; at iPad display scale (about 0.72×) it reads as depth of field.
- PNG files declare sRGB with PNG's own `sRGB` chunk, which ImageIO writes; there's no iCCP profile.
