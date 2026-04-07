import { getHostComponent } from 'react-native-nitro-modules';
import type {
  BlurredVideoProps,
  BlurredVideoMethods,
} from './BlurredVideo.nitro';
import BlurredVideoViewConfig from '../nitrogen/generated/shared/json/BlurredVideoViewConfig.json';

export const BlurredVideoView = getHostComponent<
  BlurredVideoProps,
  BlurredVideoMethods
>('BlurredVideoView', () => BlurredVideoViewConfig);

export type { BlurredVideoProps, BlurredVideoMethods };
