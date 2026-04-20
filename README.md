# react-native-blurred-video

Native GPU-blurred video view for React Native, built with [Nitro Modules](https://nitro.margelo.com).

Instead of doing decode → texture → shader → blur on the JS/Skia side every frame, this library hands video off to the OS compositor:

- **iOS:** `AVPlayerLayer` + `UIVisualEffectView` overlay
- **Android:** `ExoPlayer` + `RenderEffect.createBlurEffect()` (API 31+)

Result: zero flicker, zero frame timing games, instant first frame.

## Install

```sh
npm install react-native-blurred-video react-native-nitro-modules
cd ios && pod install
```

Then generate Nitro bindings:

```sh
npx nitro-codegen
```

## Usage

```tsx
import { BlurredVideoView } from 'react-native-blurred-video';

<BlurredVideoView
  source={videoUri}
  paused={false}
  looping
  blurRadius={7}
  thumbnailSource={thumbnailUri}
  rotation={0}
  style={{ width: '100%', height: 300 }}
/>
```

## Props

| Prop              | Type      | Description                               |
| ----------------- | --------- | ----------------------------------------- |
| `source`          | `string`  | Video URL                                 |
| `paused`          | `boolean` | Pause/play                                |
| `looping`         | `boolean` | Loop video                                |
| `blurRadius`      | `number`  | Blur radius (Android only; iOS uses system blur) |
| `thumbnailSource` | `string`  | Poster image shown until first frame      |
| `enableThumbnail` | `boolean` | Auto-extract a poster frame from `source` when `thumbnailSource` is empty |
| `showVideo`       | `boolean` | Defaults to `false`. Set `true` to create the player and start playback; set `false` to tear it down and keep only the (blurred) thumbnail. Useful for carousels where only the active cover should play |
| `rotation`        | `number`  | `0` or `90`                               |

### `showVideo` / carousel pattern

Mount every cover with `showVideo={false}` and flip it to `true` only for the currently visible item. The view will render a blurred thumbnail in the off state (no ExoPlayer / AVPlayer allocated) and spin up a real player the moment you flip it on. This keeps a 20-item carousel from running 20 decoders in parallel.

## License

MIT
