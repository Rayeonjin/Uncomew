# 앱 아이콘

폴더 속 공간을 살펴보는 고양이입니다. 크림색 고양이와 짙은 청록색 바탕으로, 작은 Dock 아이콘에서도 구분되도록 만들었습니다.

- `AppIcon.png`: 이미지 생성 도구로 제작한 원본. 모서리 바깥은 투명합니다.
- `AppIcon.icns`: macOS 앱 번들에 포함하는 아이콘. 일반 앱 빌드에서는 이 파일을 그대로 복사합니다.
- 원본 변경 후 저장소 최상위에서 `bash scripts/build-icon.sh`를 실행하면 16~1024px 표현을 다시 만듭니다.

2026-11-16 내장 이미지 생성 도구에 사용한 프롬프트:

> Create one polished macOS app icon for Uncomew, a friendly lightweight disk space inspector. 1024x1024 square. A single curious cream-colored cat face peeks over a simple open folder; a large circular magnifying glass reveals one bright empty space inside the folder. Bold simplified silhouette, restrained warm ivory and muted deep teal, subtle dimensional shading like a carefully crafted native Mac app icon. Readable at tiny Dock sizes. Rounded square teal tile centered with generous consistent margins and genuinely transparent pixels outside the rounded tile. No lettering, no numbers, no watermark, no surrounding scene, no multiple options, no astronaut, no broom, no trash can. Friendly but understated, not a busy cartoon. This is the final icon artwork, not a mockup.
