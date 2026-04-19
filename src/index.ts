import { getHostComponent, NitroModules } from 'react-native-nitro-modules';
import type {
  BlurredVideoProps,
  BlurredVideoMethods,
  VideoThumbnailGenerator,
} from './BlurredVideo.nitro';
import BlurredVideoViewConfig from '../nitrogen/generated/shared/json/BlurredVideoViewConfig.json';

export const BlurredVideoView = getHostComponent<
  BlurredVideoProps,
  BlurredVideoMethods
>('BlurredVideoView', () => BlurredVideoViewConfig);

const ThumbnailGenerator =
  NitroModules.createHybridObject<VideoThumbnailGenerator>(
    'VideoThumbnailGenerator'
  );

/**
 * Extract a frame from a video as a JPEG. Returns a `file://` URI that can be
 * passed to `<Image source={{ uri }} />` or to `BlurredVideoView`'s
 * `thumbnailSource` prop.
 *
 * Results are cached in the app's cache directory keyed by
 * (videoPath, timeMs, maxSize), so repeat calls are free.
 */
export function generateVideoThumbnail(
  videoPath: string,
  timeMs: number = 100,
  maxSize: number = 512
): Promise<string> {
  return ThumbnailGenerator.generateThumbnail(videoPath, timeMs, maxSize);
}

export type { BlurredVideoProps, BlurredVideoMethods };
