# prepare_label3d_poses.py
import argparse
import json
import os
import re
import numpy as np
import scipy.io
import glob

def parse_basenumber_from_path(path_str):
    """
    Extracts a number from a filename like '...frame_000123.png' -> 123
    Returns None if no number is found.
    """
    match = re.search(r'frame_(\d+)\.(?:png|jpg|jpeg|bmp|tiff)$\Z', os.path.basename(path_str), re.IGNORECASE)
    if match:
        return int(match.group(1))
    match_simple = re.search(r'(\d+)\.(?:png|jpg|jpeg|bmp|tiff)$\Z', os.path.basename(path_str), re.IGNORECASE)
    if match_simple:
        return int(match_simple.group(1))
    return None

def main():
    parser = argparse.ArgumentParser(
        description="Prepare precomputed 2D poses from JSON files for Label3D by aggregating all frames and instances.",
        formatter_class=argparse.ArgumentDefaultsHelpFormatter,
    )
    parser.add_argument(
        "--json-dir",
        required=True,
        help="Directory containing Cam_XXX_results.json files.",
    )
    parser.add_argument(
        "--output-mat-file",
        required=True,
        help="Path for the output .mat file (e.g., all_poses_for_label3d.mat).",
    )
    parser.add_argument(
        "--skeleton-file",
        required=True,
        help='Path to the base skeleton .mat file (e.g., coco17_skeleton.mat), ' \
             'expected to contain a \'joint_names\' field.'
    )
    parser.add_argument(
        "--kpt-score-threshold",
        type=float,
        default=0.0,
        help="Minimum keypoint confidence score to consider a keypoint valid. Points below this are set to NaN.",
    )
    args = parser.parse_args()

    print("Initializing and discovering data...")

    if not os.path.exists(args.skeleton_file):
        parser.error(f"Skeleton file not found: {args.skeleton_file}")
        return
    
    try:
        skel_data = scipy.io.loadmat(args.skeleton_file)
        if 'joint_names' not in skel_data:
            parser.error(f"\'joint_names\' not found in skeleton file: {args.skeleton_file}")
            return
        num_keypoints_per_instance = skel_data['joint_names'].size
        if num_keypoints_per_instance == 0:
            parser.error(f"Skeleton file {args.skeleton_file} indicates 0 joint_names (size is 0).")
            return
        print(f"  DEBUG: Loaded skeleton. 'joint_names' field has .size = {num_keypoints_per_instance}") # Debug print
    except Exception as e:
        parser.error(f"Could not load or parse skeleton file {args.skeleton_file}: {e}")
        return
        
    # --- Discover Camera JSON files ---
    json_file_pattern = os.path.join(args.json_dir, "Cam_*_results.json")
    discovered_json_files = sorted(glob.glob(json_file_pattern))

    if not discovered_json_files:
        parser.error(f"No 'Cam_*_results.json' files found in {args.json_dir}")
        return

    processed_camera_names = []
    camera_json_data_map = {} # Store loaded JSON data to avoid re-reading

    for json_path in discovered_json_files:
        cam_name_match = re.search(r"(Cam_\d+)_results\.json", os.path.basename(json_path))
        if cam_name_match:
            cam_name = cam_name_match.group(1)
            processed_camera_names.append(cam_name)
            try:
                with open(json_path, 'r') as f:
                    camera_json_data_map[cam_name] = json.load(f)
            except json.JSONDecodeError as e:
                print(f"    Error decoding JSON for {cam_name}: {e}. Skipping this camera for discovery.")
                processed_camera_names.remove(cam_name) # Remove if data can't be loaded
            except Exception as e:
                 print(f"    Unexpected error loading JSON for {cam_name}: {e}. Skipping this camera for discovery.")
                 if cam_name in processed_camera_names: processed_camera_names.remove(cam_name)


    if not processed_camera_names:
        parser.error(f"No valid camera JSON files could be processed from {args.json_dir}")
        return
    
    num_processed_cams = len(processed_camera_names)
    print(f"  Will process data for {num_processed_cams} cameras: {processed_camera_names}")

    # --- Discover all unique frame IDs and instance IDs ---
    all_frame_ids_set = set()
    all_instance_ids_set = set()

    for cam_name in processed_camera_names:
        data = camera_json_data_map.get(cam_name)
        if not data: continue

        is_video_json = "instance_info" in data
        is_image_json = "image_predictions" in data

        if is_video_json:
            for frame_info in data.get("instance_info", []):
                frame_id = frame_info.get("frame_id")
                if frame_id is not None:
                    all_frame_ids_set.add(frame_id)
                for inst in frame_info.get("instances", []):
                    inst_id = inst.get("instance_id")
                    if inst_id is not None:
                        all_instance_ids_set.add(str(inst_id)) # Ensure instance_id is string for consistent sorting
        elif is_image_json:
            for img_pred in data.get("image_predictions", []):
                img_path = img_pred.get("image_path")
                if img_path:
                    frame_id = parse_basenumber_from_path(img_path)
                    if frame_id is not None:
                        all_frame_ids_set.add(frame_id)
                for inst in img_pred.get("instances", []):
                    inst_id = inst.get("instance_id")
                    if inst_id is not None:
                        all_instance_ids_set.add(str(inst_id))
    
    if not all_frame_ids_set:
        parser.error("No frames found across any JSON files.")
        return
    if not all_instance_ids_set:
        parser.error("No instances with 'instance_id' found across any JSON files.")
        return

    sorted_frame_ids = sorted(list(all_frame_ids_set))
    sorted_instance_ids = sorted(list(all_instance_ids_set)) # Sorted list of unique string instance IDs

    num_distinct_instances = len(sorted_instance_ids)
    num_processed_frames = len(sorted_frame_ids)
    total_num_markers = num_distinct_instances * num_keypoints_per_instance
    
    print(f"  Discovered {num_distinct_instances} unique instance IDs: {sorted_instance_ids}")
    print(f"  Discovered {num_processed_frames} unique frame IDs, from {min(sorted_frame_ids)} to {max(sorted_frame_ids)}")
    print(f"  Total markers to store: {total_num_markers} ({num_distinct_instances} instances * {num_keypoints_per_instance} kpts)")

    # --- Prepare data arrays ---
    cam_name_to_idx_map = {name: i for i, name in enumerate(processed_camera_names)}
    frame_id_to_mat_idx_map = {fid: i for i, fid in enumerate(sorted_frame_ids)}
    instance_id_to_slot_idx_map = {iid: i for i, iid in enumerate(sorted_instance_ids)} # String IDs to 0-based slot

    cam_points_data = np.full(
        (total_num_markers, num_processed_cams, 2, num_processed_frames),
        np.nan,
        dtype=float,
    )
    status_data = np.zeros(
        (total_num_markers, num_processed_cams, num_processed_frames),
        dtype=np.uint8,
    )

    print("\nPopulating data arrays...")
    for cam_idx, cam_name in enumerate(processed_camera_names):
        data = camera_json_data_map.get(cam_name)
        if not data: continue
        print(f"  Processing camera: {cam_name} (Index: {cam_idx})")

        is_video_json = "instance_info" in data
        is_image_json = "image_predictions" in data

        current_frames_in_cam = []
        if is_video_json:
            current_frames_in_cam = data.get("instance_info", [])
        elif is_image_json:
            current_frames_in_cam = data.get("image_predictions", [])

        for frame_content in current_frames_in_cam:
            actual_frame_id = None
            instances_for_frame = []

            if is_video_json:
                actual_frame_id = frame_content.get("frame_id")
                instances_for_frame = frame_content.get("instances", [])
            elif is_image_json:
                img_path = frame_content.get("image_path")
                if img_path:
                    actual_frame_id = parse_basenumber_from_path(img_path)
                instances_for_frame = frame_content.get("instances", [])

            if actual_frame_id is None or actual_frame_id not in frame_id_to_mat_idx_map:
                continue # Frame not in our global list of frames to process

            mat_frame_idx = frame_id_to_mat_idx_map[actual_frame_id]

            for inst_json in instances_for_frame:
                json_instance_id_str = str(inst_json.get("instance_id")) # Ensure string
                if json_instance_id_str not in instance_id_to_slot_idx_map:
                    continue # Instance ID not in our global list (e.g. None or new)

                instance_slot_idx = instance_id_to_slot_idx_map[json_instance_id_str]
                
                kps_list = inst_json.get("keypoints", [])
                scores_list = inst_json.get("keypoint_scores", [])

                if len(kps_list) == num_keypoints_per_instance and \
                   (not scores_list or len(scores_list) == num_keypoints_per_instance):
                    
                    marker_offset = instance_slot_idx * num_keypoints_per_instance
                    for joint_idx in range(num_keypoints_per_instance):
                        global_marker_idx = marker_offset + joint_idx
                        point_xy = kps_list[joint_idx]
                        score = scores_list[joint_idx] if scores_list and joint_idx < len(scores_list) else args.kpt_score_threshold

                        if score >= args.kpt_score_threshold and \
                           len(point_xy) == 2 and \
                           not (point_xy[0] is None or point_xy[1] is None):
                            try:
                                px, py = float(point_xy[0]), float(point_xy[1])
                                cam_points_data[global_marker_idx, cam_idx, :, mat_frame_idx] = [px, py]
                                status_data[global_marker_idx, cam_idx, mat_frame_idx] = 1 # Initialized
                            except (ValueError, TypeError):
                                pass # Keep as NaN if conversion fails
                # else: print(f"Warning: Kp/score mismatch for {cam_name}, frame {actual_frame_id}, inst {json_instance_id_str}")


    print(f"\nSaving formatted data to: {args.output_mat_file}")
    output_data_dict = {
        "precomputed_camPoints": cam_points_data,
        "precomputed_status": status_data,
        "processed_camera_names": np.array(processed_camera_names, dtype=object),
        "processed_frame_ids": np.array(sorted_frame_ids, dtype=int),
        "discovered_instance_ids": np.array(sorted_instance_ids, dtype=object), # Saved as strings
        "num_keypoints_per_instance": num_keypoints_per_instance,
        "source_json_dir": args.json_dir,
        "skeleton_file": args.skeleton_file,
        "kpt_score_threshold_applied": args.kpt_score_threshold
    }
    
    try:
        scipy.io.savemat(args.output_mat_file, output_data_dict)
        print("Successfully saved .mat file.")
    except Exception as e:
        print(f"Error saving .mat file: {e}")

if __name__ == "__main__":
    main()