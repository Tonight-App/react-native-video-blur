import type {
  HybridView,
  HybridViewProps,
  HybridViewMethods,
} from 'react-native-nitro-modules';

export interface BlurredVideoProps extends HybridViewProps {
  source: string;
  paused: boolean;
  looping: boolean;
  blurRadius: number;
  thumbnailSource: string;
  /** 0 or 90 */
  rotation: number;
}

export interface BlurredVideoMethods extends HybridViewMethods {}

export type BlurredVideoView = HybridView<
  BlurredVideoProps,
  BlurredVideoMethods
>;
