import type {
  HybridView,
  HybridViewProps,
  HybridViewMethods,
  HybridObject,
} from 'react-native-nitro-modules';

export interface BlurredVideoProps extends HybridViewProps {
  source: string;
  paused: boolean;
  looping: boolean;
  blurRadius: number;
  thumbnailSource: string;
  /**
   * When true, view extracts a thumbnail (first frame @ ~100ms, capped 512px)
   * from `source` on a background thread and shows it blurred while the video
   * loads. Cached on disk. Ignored if `thumbnailSource` is set.
   */
  enableThumbnail: boolean;
  /**
   * When false, the underlying video player is not created at all — only the
   * thumbnail is rendered. Use this to skip real decode cost for off-screen
   * items in a scrolling list.
   */
  showVideo: boolean;
  /** 0 or 90 */
  rotation: number;
}

export interface BlurredVideoMethods extends HybridViewMethods {}

export type BlurredVideoView = HybridView<
  BlurredVideoProps,
  BlurredVideoMethods
>;

export interface VideoThumbnailGenerator
  extends HybridObject<{ ios: 'swift'; android: 'kotlin' }> {
  /**
   * Extracts a single frame from a video at the given timestamp and writes it
   * to the app's cache directory as JPEG. Returns a `file://` URI.
   *
   * @param videoPath  `file://` path or remote URL of the video
   * @param timeMs     Timestamp in milliseconds (default 100)
   * @param maxSize    Max edge in px for the output bitmap (default 512)
   */
  generateThumbnail(
    videoPath: string,
    timeMs: number,
    maxSize: number
  ): Promise<string>;
}
