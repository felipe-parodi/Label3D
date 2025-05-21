# extract_training_imgs.py

"""

"""

import os
import json
import cv2
import re
import argparse
import logging
from pathlib import Path
import random # Added for random selection in test mode

from coco_utils import coco_labels_utils as clu
from coco_utils import coco_viz_utils as cvu
COCO_UTILS_AVAILABLE = True
logging.info("coco_utils imported successfully.")

# Setup logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')

def image_has_annotations(coco_data, image_id):
    """Checks if a given image_id has any annotations."""
    if 'annotations' not in coco_data:
        return False
    for ann in coco_data['annotations']:
        if ann.get('image_id') == image_id:
            return True
    return False

def extract_frames(coco_json_path, video_dir, output_image_dir, test_mode=False, frames_to_exclude=None):
    """
    Loads COCO JSON, extracts frame information, and saves frames from videos.
    In test_mode, processes a randomly selected valid image that also has annotations.
    Skips frames if their frame number string is in frames_to_exclude list.
    Returns the image_id of the processed image if in test_mode and successful,
    and the full coco_data dictionary.
    """
    if frames_to_exclude is None:
        frames_to_exclude = []
        
    output_image_dir_path = Path(output_image_dir)
    output_image_dir_path.mkdir(parents=True, exist_ok=True)
    logging.info(f"Output directory: {output_image_dir_path}")

    processed_image_id_for_test = None
    full_coco_data = None

    try:
        with open(coco_json_path, 'r') as f:
            full_coco_data = json.load(f)
        logging.info(f"Successfully loaded COCO JSON from: {coco_json_path}")
    except FileNotFoundError:
        logging.error(f"COCO JSON file not found: {coco_json_path}")
        return None, None
    except json.JSONDecodeError:
        logging.error(f"Error decoding COCO JSON: {coco_json_path}")
        return None, None
    except Exception as e:
        logging.error(f"Unexpected error loading COCO JSON: {e}")
        return None, None

    if 'images' not in full_coco_data or not full_coco_data['images']: # Check if images list is not empty
        logging.error("COCO JSON missing 'images' key or 'images' list is empty.")
        return None, full_coco_data

    filename_pattern = re.compile(r"Cam_(\d+)_frame_(\d+)\.jpg")
    extracted_count = 0
    failed_count = 0
    excluded_by_rule_count = 0

    images_to_process = list(full_coco_data['images']) # Create a copy

    if test_mode:
        random.shuffle(images_to_process) # Shuffle for random test image
        logging.info("Test mode: Shuffled images for random selection.")

    for image_info in images_to_process:
        img_file_name = image_info.get('file_name')
        current_image_id = image_info.get('id')

        if not img_file_name:
            logging.warning(f"Skipping image entry due to missing 'file_name': ID {current_image_id or 'Unknown'}")
            failed_count += 1
            continue

        match = filename_pattern.match(img_file_name)
        if not match:
            logging.warning(f"Filename format mismatch for {img_file_name}. Skipping.")
            failed_count += 1
            continue

        camera_id_str = match.group(1)
        frame_number_str = match.group(2) 

        if str(int(frame_number_str)) in frames_to_exclude:
            logging.info(f"Excluding {img_file_name} based on exclusion rule (frame {frame_number_str}).")
            excluded_by_rule_count +=1
            if test_mode: 
                processed_image_id_for_test = None 
                continue 
            else:
                continue

        try:
            frame_number = int(frame_number_str)
            if frame_number <= 0:
                logging.warning(f"Invalid frame number {frame_number} for {img_file_name}. Skipping.")
                failed_count += 1
                if test_mode: processed_image_id_for_test = None 
                continue
        except ValueError:
            logging.warning(f"Could not parse frame number '{frame_number_str}' for {img_file_name}. Skipping.")
            failed_count += 1
            if test_mode: processed_image_id_for_test = None
            continue

        video_filename = f"Cam_{camera_id_str}.mp4"
        video_path = os.path.join(video_dir, video_filename)
        output_frame_path = os.path.join(output_image_dir_path, img_file_name)
        
        image_is_available_or_extracted = False
        
        # OFF-BY-ONE TEST: frame_number is 1-indexed from filename.
        # Option 1 (Original): cv2_frame_index = frame_number - 1  (if filename "1" is video's first frame, index 0)
        # Option 2 (Current Test): cv2_frame_index = frame_number (if filename "1" is video's second frame, index 1)
        cv2_frame_index = frame_number-1 # Using this for the off-by-one test. Revert to frame_number - 1 if needed.

        if os.path.exists(output_frame_path):
            logging.info(f"Image {output_frame_path} already exists.")
            extracted_count += 1 
            image_is_available_or_extracted = True
            if test_mode: # If it exists, check for annotations before breaking
                if image_has_annotations(full_coco_data, current_image_id):
                    processed_image_id_for_test = current_image_id
                    logging.info(f"Using existing image (ID: {current_image_id}, File: {img_file_name}) with annotations for test.")
                    break # Found suitable existing image
                else:
                    logging.info(f"Existing image (ID: {current_image_id}, File: {img_file_name}) has no annotations. Trying another for test.")
                    processed_image_id_for_test = None # Reset and continue
                    continue 
            else: # Not test mode, just continue to next image if it exists
                continue
        else: # Image does not exist, try to extract it
            if not os.path.exists(video_path):
                logging.warning(f"Video file not found: {video_path} for {img_file_name}. Skipping.")
                failed_count += 1
                if test_mode: processed_image_id_for_test = None
                continue

            cap = cv2.VideoCapture(video_path)
            if not cap.isOpened():
                logging.warning(f"Could not open video: {video_path} for {img_file_name}. Skipping.")
                failed_count += 1
                if test_mode: processed_image_id_for_test = None
                cap.release()
                continue
            
            logging.info(f"Attempting to fetch frame at 0-indexed position {cv2_frame_index} for {img_file_name} (original filename frame: {frame_number_str})")
            cap.set(cv2.CAP_PROP_POS_FRAMES, cv2_frame_index)
            ret, frame = cap.read()
            
            if ret:
                try:
                    cv2.imwrite(output_frame_path, frame)
                    logging.info(f"Successfully extracted and saved: {output_frame_path}")
                    extracted_count += 1
                    image_is_available_or_extracted = True
                except Exception as e:
                    logging.error(f"Could not write frame {img_file_name} to {output_frame_path}: {e}")
                    failed_count += 1
            else:
                total_frames = int(cap.get(cv2.CAP_PROP_FRAME_COUNT))
                logging.warning(f"Could not read frame {cv2_frame_index} (for filename frame {frame_number_str}) from {video_path} (total: {total_frames}). Skipping {img_file_name}.")
                failed_count += 1
            cap.release()

        # After attempting extraction or confirming existence
        if test_mode:
            if image_is_available_or_extracted:
                if image_has_annotations(full_coco_data, current_image_id):
                    processed_image_id_for_test = current_image_id
                    logging.info(f"Test mode: Image ID {current_image_id} (File: {img_file_name}) is available/extracted and has annotations. Ready for visualization.")
                    break 
                else:
                    logging.info(f"Test mode: Image ID {current_image_id} (File: {img_file_name}) is available/extracted but has no annotations. Trying another.")
                    processed_image_id_for_test = None 
            else: # If it wasn't available and extraction failed
                 processed_image_id_for_test = None

    if test_mode and processed_image_id_for_test is None:
        logging.warning("Test mode: No suitable image (available/extracted and with annotations) found after checking.")

    logging.info(f"Frame extraction complete. Success: {extracted_count}, Failed/Skipped: {failed_count}, Excluded by rule: {excluded_by_rule_count}.")
    return processed_image_id_for_test, full_coco_data


def main():
    parser = argparse.ArgumentParser(description="Extract specific frames from videos based on COCO JSON.")
    parser.add_argument('--coco_json_path', type=str, 
                        default=r"A:/EnclosureProjects/inprep/freemat/code/calibration/WMcalibration/Label3D/labeling_output/output_coco.json")
    parser.add_argument('--video_dir', type=str, 
                        default=r"A:/EnclosureProjects/inprep/freemat/data/experiments/good/240528/video/experiment/fixed_timestamp/crop1min_cropped_videos")
    parser.add_argument('--output_image_dir', type=str, 
                        default=r"A:/EnclosureProjects/inprep/freemat/data/experiments/good/240528/video/experiment/fixed_timestamp/crop1min_cropped_videos/imgs_extracted_test")
    parser.add_argument('--test_single', action='store_true', help='Run in test mode: process a random valid image with annotations and visualize.')
    parser.add_argument('--frames_to_exclude', nargs='*', default=['1076', '2689'], 
                        help='List of frame number strings to exclude (e.g., "1076" "2689").')

    args = parser.parse_args()

    logging.info(f"Starting script with args: {args}")
    
    frames_to_exclude_str = [str(f) for f in args.frames_to_exclude]

    processed_test_image_id, coco_data_dict = extract_frames(
        args.coco_json_path, 
        args.video_dir, 
        args.output_image_dir,
        test_mode=args.test_single,
        frames_to_exclude=frames_to_exclude_str
    )

    if args.test_single and processed_test_image_id is not None and COCO_UTILS_AVAILABLE and coco_data_dict:
        logging.info(f"Test mode: Visualizing keypoints for image ID {processed_test_image_id} from {args.output_image_dir}")
        try:
            cvu.visualize_keypoints(coco_data_dict, processed_test_image_id, args.output_image_dir)
            logging.info(f"Visualization attempted for image ID {processed_test_image_id}.")
        except Exception as e:
            logging.error(f"Error during visualization for image ID {processed_test_image_id}: {e}")
    elif args.test_single and processed_test_image_id is None:
        logging.warning("Test mode was active, but no image suitable for visualization (available/extracted and with annotations) was found.")
    elif args.test_single and not COCO_UTILS_AVAILABLE:
        logging.warning("Test mode: coco_utils not available, skipping visualization.")

if __name__ == '__main__':
    main()





