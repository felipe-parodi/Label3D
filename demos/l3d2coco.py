# l3d2coco.py

# first we need to modify label3d to save 2d data if it doesnt already
# then we need to load the labeling_output mat file and inspect
# then extract and load the 2d data
# then format the metadata and data for COCO-json file

import json
import os
import numpy as np
import scipy.io as sio
from datetime import datetime

def print_mat_structure(data, name="Data", indent=0):
    """Prints the structure and types of data loaded from a .mat file."""
    prefix = "  " * indent
    if isinstance(data, dict):
        print(f"{prefix}{name} (dict):")
        for key, value in data.items():
            if key.startswith('__'): continue # Skip scipy internal keys
            print_mat_structure(value, f"Key: '{key}'", indent + 1)
    elif isinstance(data, np.ndarray):
        print(f"{prefix}{name} (numpy.ndarray): shape={data.shape}, dtype={data.dtype}")
        if data.dtype == 'object' and data.size > 0 :
             # If it's an object array, try to print structure of the first element
            print(f"{prefix}  (Attempting to show structure of first element of object array)")
            if data.ndim == 1 and data.size > 0:
                print_mat_structure(data[0], f"Element [0]", indent + 1)
            elif data.ndim > 1 and data.size > 0:
                 print_mat_structure(data.flat[0], f"Element .flat[0]", indent + 1)

    elif isinstance(data, list):
        print(f"{prefix}{name} (list, len={len(data)}):")
        if data:
            print_mat_structure(data[0], "Element [0]", indent + 1)
    elif isinstance(data, (str, int, float, bool)):
        print(f"{prefix}{name} ({type(data).__name__}): {data}")
    else:
        print(f"{prefix}{name} (type: {type(data).__name__}): {data}")


def l3d_to_coco(l3d_mat_path, base_skeleton_mat_path, output_coco_path):
    """
    Converts Label3D .mat output to COCO format.

    Args:
        l3d_mat_path (str): Path to the Label3D .mat file.
        base_skeleton_mat_path (str): Path to the base skeleton .mat file 
                                      (e.g., coco17_skeleton.mat).
        output_coco_path (str): Path to save the output COCO JSON file.
    """

    print(f"Loading Label3D data from: {l3d_mat_path}")
    l3d_data = sio.loadmat(l3d_mat_path, simplify_cells=True)

    print(f"Loading base skeleton data from: {base_skeleton_mat_path}")
    base_skeleton_data = sio.loadmat(base_skeleton_mat_path, simplify_cells=True)

    print("\n--- Structure of l3d_data ---")
    print_mat_structure(l3d_data, "l3d_data")
    print("\n--- Structure of base_skeleton_data ---")
    print_mat_structure(base_skeleton_data, "base_skeleton_data")
    print("\n---------------------------------\n")

    # --- Extract necessary data from Label3D .mat ---
    all_cam_points_2d = l3d_data['camPoints'] # (nMarkers, nCams, 2, nSessionFrames)
    print(f"Loaded all_cam_points_2d with shape: {all_cam_points_2d.shape} and dtype: {all_cam_points_2d.dtype}")

    status = l3d_data['status']                 # (nMarkers, nCams, nSessionFrames)
    image_size_l3d = l3d_data['imageSize']      # (nCams, 2) -> [Height, Width]
    
    # framesToLabel might be (1, nSessionFrames) or (nSessionFrames, 1)
    frames_to_label = np.array(l3d_data['framesToLabel']).flatten()
    
    n_animals_in_session = l3d_data.get('nAnimalsInSession')
    if n_animals_in_session is None:
        # Try to infer if 'skeleton' has 'nAnimals' field or based on total markers
        # This is a fallback, ideally nAnimalsInSession is saved.
        print("Warning: 'nAnimalsInSession' not found in .mat file. Attempting to infer.")
        if 'skeleton' in l3d_data and isinstance(l3d_data['skeleton'], dict) and 'nAnimals' in l3d_data['skeleton']:
            n_animals_in_session = l3d_data['skeleton']['nAnimals']
            print(f"  Inferred n_animals_in_session = {n_animals_in_session} from skeleton.nAnimals")
        else:
            # Further inference might be needed or raise an error
            raise ValueError("'nAnimalsInSession' not found and could not be inferred. Please ensure it's saved in the .mat or provide it.")
    n_animals_in_session = int(n_animals_in_session)


    camera_names_l3d_raw = l3d_data.get('cameraNamesToSave')
    parsed_camera_names = []
    if camera_names_l3d_raw is not None:
        if isinstance(camera_names_l3d_raw, str):
            # Single camera name saved as a simple string (less likely with cellfun)
            parsed_camera_names = [camera_names_l3d_raw]
        elif isinstance(camera_names_l3d_raw, np.ndarray) and camera_names_l3d_raw.dtype == 'object':
            # Expected: object array where each element is a Python string due to cellfun(@char, ...)
            # and simplify_cells=True
            for item in camera_names_l3d_raw.flatten():
                if isinstance(item, str):
                    parsed_camera_names.append(item.strip())
                elif isinstance(item, bytes): # Fallback for bytes
                    try:
                        parsed_camera_names.append(item.decode('utf-8').strip())
                    except UnicodeDecodeError:
                        print(f"Warning: Could not decode bytes cameraName item: {item}. Skipping.")
                else:
                    # This case should be less likely now with the MATLAB char conversion
                    print(f"Warning: Unexpected item type {type(item)} in cameraNamesToSave array: {item}. Trying str().")
                    parsed_camera_names.append(str(item).strip())
        elif isinstance(camera_names_l3d_raw, list): 
            # Fallback if it's loaded as a list of strings (also good)
            parsed_camera_names = [str(name).strip() for name in camera_names_l3d_raw]
        else:
            print(f"Warning: cameraNamesToSave is of an unexpected type: {type(camera_names_l3d_raw)}.")

    if not parsed_camera_names or len(parsed_camera_names) != all_cam_points_2d.shape[1]:
        if parsed_camera_names:
             print(f"Warning: Number of parsed camera names ({len(parsed_camera_names)}) does not match number of cameras in data ({all_cam_points_2d.shape[1]}). Regenerating default names.")
        else:
            print("Warning: 'cameraNamesToSave' processing resulted in an empty list or was not found. Generating default names.")
        num_cams_from_data = all_cam_points_2d.shape[1]
        camera_names_l3d = [f"Cam_default_{i+1}" for i in range(num_cams_from_data)]
    else:
        camera_names_l3d = parsed_camera_names


    # --- Skeleton and Keypoint Info ---
    # Multi-animal skeleton from Label3D output
    l3d_skeleton_joint_names = l3d_data['skeleton']['joint_names']
    if isinstance(l3d_skeleton_joint_names, str): # single joint name
        l3d_skeleton_joint_names = [l3d_skeleton_joint_names]
    
    num_total_markers = all_cam_points_2d.shape[0]

    # Base skeleton for COCO category definition
    base_skel_joint_names_raw = base_skeleton_data['joint_names']
    if isinstance(base_skel_joint_names_raw, str):
        base_skel_joint_names = [base_skel_joint_names_raw]
    elif isinstance(base_skel_joint_names_raw, np.ndarray) and base_skel_joint_names_raw.dtype == 'object':
        base_skel_joint_names = [str(name) for name in base_skel_joint_names_raw.flatten()]
    elif isinstance(base_skel_joint_names_raw, list):
        base_skel_joint_names = [str(name) for name in base_skel_joint_names_raw]
    else: # Assuming it's a direct list of strings or similar if simplify_cells worked well
        base_skel_joint_names = list(base_skel_joint_names_raw)


    base_skel_edges_raw = base_skeleton_data['joints_idx'] # MATLAB 1-based
    if isinstance(base_skel_edges_raw, np.ndarray):
        # Ensure it's a list of lists of Python integers
        base_skel_edges = (base_skel_edges_raw - 1).astype(int).tolist()
        if base_skel_edges_raw.ndim == 1 and base_skel_edges_raw.shape[0] == 2 : # A single edge loaded as 1D array
             base_skel_edges = [(base_skel_edges_raw -1).astype(int).tolist()]
        elif base_skel_edges_raw.ndim == 2:
             base_skel_edges = (base_skel_edges_raw - 1).astype(int).tolist()
        else: # Fallback for unexpected shape
             print(f"Warning: base_skel_edges_raw has unexpected shape {base_skel_edges_raw.shape}. Trying simple tolist.")
             base_skel_edges = (base_skel_edges_raw - 1).tolist()

    else: # If not a numpy array, try simple tolist (less likely after loadmat)
        print(f"Warning: base_skel_edges_raw is not a numpy array (type: {type(base_skel_edges_raw)}). Attempting direct conversion.")
        # Assuming it might be a list of lists already, just ensure inner elements are int and 0-based
        base_skel_edges = [[int(idx - 1) for idx in edge] for edge in base_skel_edges_raw]


    num_base_keypoints = len(base_skel_joint_names)
    
    if num_total_markers == 0 and n_animals_in_session > 0:
        print("Warning: num_total_markers is 0, but n_animals_in_session > 0. Assuming keypoints_per_animal from base skeleton.")
        keypoints_per_animal = num_base_keypoints
    elif n_animals_in_session == 0 and num_total_markers > 0:
        # This case is ambiguous. If one animal, keypoints_per_animal = num_total_markers.
        # For safety, let's assume if n_animals_in_session is 0 but there are markers, it's one animal.
        print("Warning: n_animals_in_session is 0, but num_total_markers > 0. Assuming 1 animal.")
        n_animals_in_session = 1
        keypoints_per_animal = num_total_markers
    elif n_animals_in_session == 0 and num_total_markers == 0:
        print("Warning: No markers and no animals. COCO file might be empty.")
        keypoints_per_animal = 0 # Or handle as an error
    else:
        if num_total_markers % n_animals_in_session != 0:
            raise ValueError(
                f"Total markers ({num_total_markers}) is not evenly divisible by "
                f"nAnimalsInSession ({n_animals_in_session})."
            )
        keypoints_per_animal = num_total_markers // n_animals_in_session

    if keypoints_per_animal != num_base_keypoints:
         print(
            f"Warning: Keypoints per animal in Label3D ({keypoints_per_animal}) "
            f"does not match base skeleton keypoints ({num_base_keypoints}). "
            f"COCO category will use base skeleton, annotations will use Label3D count."
        )
        # This implies the `l3d_skeleton_joint_names` are for one animal if `keypoints_per_animal`
        # is used for slicing, but the COCO output format for keypoints list must match the category's definition.
        # For simplicity, we'll assume the COCO category defines num_base_keypoints,
        # and each annotation will provide that many [x,y,v] triplets.
        # If keypoints_per_animal from L3D is different, data needs careful mapping or truncation/padding.
        # Let's assume keypoints_per_animal from L3D IS the number of keypoints for one animal instance.


    # --- Initialize COCO Structure ---
    coco_output = {
        "images": [],
        "annotations": [],
        "categories": []
    }

    # --- Populate Categories (using base skeleton) ---
    category_name = "monkey" # Or make this an argument
    coco_output["categories"].append({
        "id": 1, # Assuming one category
        "name": category_name,
        "supercategory": "monkey",
        "keypoints": base_skel_joint_names,
        "skeleton": base_skel_edges
    })
    category_id = 1

    # --- Populate Images and Annotations ---
    image_id_counter = 0
    annotation_id_counter = 0
    
    # Label3D status enums: unlabeled=0, initialized=1, labeled=2, invisible=3
    L3D_STATUS_UNLABELED = 0
    L3D_STATUS_INITIALIZED = 1
    L3D_STATUS_LABELED = 2
    L3D_STATUS_INVISIBLE = 3

    num_session_frames = all_cam_points_2d.shape[3]
    num_cameras = all_cam_points_2d.shape[1]

    for frame_s_idx in range(num_session_frames):
        original_frame_id = int(frames_to_label[frame_s_idx])

        for cam_idx in range(num_cameras):
            image_id_counter += 1
            current_image_id = image_id_counter

            img_height = int(image_size_l3d[cam_idx, 0])
            img_width = int(image_size_l3d[cam_idx, 1])
            cam_name = camera_names_l3d[cam_idx] if cam_idx < len(camera_names_l3d) else f"Cam_{cam_idx+1}"
            if not isinstance(cam_name, str): cam_name = str(cam_name) # Ensure string

            coco_output["images"].append({
                "id": current_image_id,
                "width": img_width,
                "height": img_height,
                "file_name": f"{cam_name}_frame_{original_frame_id:06d}.jpg", # Example filename
            })

            if n_animals_in_session == 0 : continue

            for animal_inst_idx in range(n_animals_in_session):
                marker_start_idx = animal_inst_idx * keypoints_per_animal
                marker_end_idx = marker_start_idx + keypoints_per_animal
                
                if marker_end_idx > num_total_markers:
                    print(f"DEBUG: Skipping annotation. Animal {animal_inst_idx}, marker_end_idx {marker_end_idx} > num_total_markers {num_total_markers}")
                    continue

                if not (marker_start_idx < marker_end_idx <= all_cam_points_2d.shape[0] and \
                        cam_idx < all_cam_points_2d.shape[1] and \
                        frame_s_idx < all_cam_points_2d.shape[3]):
                    print(f"DEBUG: Skipping annotation due to invalid slice. Animal {animal_inst_idx}, Cam {cam_idx}, Frame_s {frame_s_idx}")
                    continue

                instance_kps_2d = all_cam_points_2d[marker_start_idx:marker_end_idx, cam_idx, :, frame_s_idx]
                instance_status_vals = status[marker_start_idx:marker_end_idx, cam_idx, frame_s_idx]

                if frame_s_idx < 2 and cam_idx < 2 and animal_inst_idx < 1: # Limit debug printing to avoid flooding
                    print(f"\nDEBUG: Processing ImageID={current_image_id}, Cam={cam_name} (idx {cam_idx}), Frame_s_idx={frame_s_idx} (orig id {original_frame_id}), Animal_inst_idx={animal_inst_idx}")
                    print(f"  Markers slice: {marker_start_idx} to {marker_end_idx-1}")
                    print(f"  Instance KPs 2D (all_cam_points_2d slice, shape {instance_kps_2d.shape}):\n{instance_kps_2d}")
                    print(f"  Instance Status (status slice, shape {instance_status_vals.shape}):\n{instance_status_vals}")

                coco_keypoints_flat = []
                num_labeled_kps_for_instance = 0
                visible_xs = []
                visible_ys = []

                # Iterate up to num_base_keypoints for COCO output,
                # using data from instance_kps_2d (which has keypoints_per_animal)
                for kpt_i in range(num_base_keypoints):
                    x, y, v = 0, 0, 0 # Default: not labeled/visible
                    if kpt_i < keypoints_per_animal : 
                        if kpt_i < instance_kps_2d.shape[0] and kpt_i < instance_status_vals.shape[0]:
                            x_l3d = instance_kps_2d[kpt_i, 0]
                            y_l3d = instance_kps_2d[kpt_i, 1]
                            status_val = instance_status_vals[kpt_i]

                            if not np.isnan(x_l3d) and not np.isnan(y_l3d):
                                x, y = int(round(float(x_l3d))), int(round(float(y_l3d)))
                                temp_v = 0 

                                # Check if point is outside image bounds
                                if x < 0 or y < 0 or x >= img_width or y >= img_height:
                                    temp_v = 0 # Set visibility to 0 if out of bounds
                                elif status_val == L3D_STATUS_INVISIBLE:
                                    temp_v = 1 
                                elif status_val == L3D_STATUS_INITIALIZED or status_val == L3D_STATUS_LABELED:
                                    temp_v = 2 
                                
                                # DEBUG PRINT for non-NaN points:
                                if frame_s_idx < 2 and cam_idx < 2 and animal_inst_idx < 1: # Limit debug output
                                    print(f"    DEBUG_VIS: kpt_i={kpt_i}, x={x}, y={y}, status_val={status_val} => coco_v={temp_v}")
                                v = temp_v
                            # If x_l3d or y_l3d is NaN, v remains 0 (not labeled)
                        else:
                            pass # kpt_i out of bounds for instance data
                    
                    coco_keypoints_flat.extend([x, y, v])
                    if v > 0: # COCO defines num_keypoints as number of kps with v>0
                        num_labeled_kps_for_instance += 1
                    if v == 2: # For bbox, consider only visible and labeled points
                        visible_xs.append(x)
                        visible_ys.append(y)

                if frame_s_idx < 2 and cam_idx < 2 and animal_inst_idx < 1: # Mirrored debug print condition
                    print(f"  Derived COCO keypoints_flat (first few elements): {coco_keypoints_flat[:num_base_keypoints*3*2]}...")
                    print(f"  Derived num_labeled_kps_for_instance: {num_labeled_kps_for_instance}")
                    if not visible_xs:
                        print("  No visible_xs for bbox calculation for this instance.")
                    else:
                        print(f"  visible_xs count: {len(visible_xs)}")


                if not visible_xs: 
                    if num_labeled_kps_for_instance == 0: 
                        if frame_s_idx < 2 and cam_idx < 2 and animal_inst_idx < 1: # Debug print for skipping
                            print(f"  SKIPPING annotation: num_labeled_kps_for_instance is 0.")
                        continue


                annotation_id_counter += 1
                
                if visible_xs:
                    min_x_f, max_x_f = float(min(visible_xs)), float(max(visible_xs))
                    min_y_f, max_y_f = float(min(visible_ys)), float(max(visible_ys))
                    
                    # Cap bounding box coordinates to image dimensions
                    min_x_f_clipped = max(0.0, min_x_f)
                    min_y_f_clipped = max(0.0, min_y_f)
                    max_x_f_clipped = min(float(img_width -1), max_x_f)
                    max_y_f_clipped = min(float(img_height -1), max_y_f)

                    bbox_w_f = max(0.0, max_x_f_clipped - min_x_f_clipped)
                    bbox_h_f = max(0.0, max_y_f_clipped - min_y_f_clipped)
                    bbox_float = [min_x_f_clipped, min_y_f_clipped, bbox_w_f, bbox_h_f]
                else:
                    bbox_float = [0.0, 0.0, 0.0, 0.0] # Default if no visible points for bbox
                
                bbox_coco = [int(round(c)) for c in bbox_float]
                area = float(bbox_coco[2] * bbox_coco[3])

                coco_output["annotations"].append({
                    "id": annotation_id_counter,
                    "image_id": current_image_id,
                    "category_id": category_id,
                    "iscrowd": 0,
                    "area": area,
                    "bbox": bbox_coco,
                    "num_keypoints": num_labeled_kps_for_instance,
                    "keypoints": coco_keypoints_flat,
                })
    
    # --- Save COCO JSON File ---
    print(f"Saving COCO data to: {output_coco_path}")
    os.makedirs(os.path.dirname(output_coco_path), exist_ok=True)
    with open(output_coco_path, 'w') as f:
        json.dump(coco_output, f, indent=4)
    print("Conversion complete.")

if __name__ == '__main__':
    # l3d_mat_file = "path/to/your/Label3D_output.mat" 
    l3d_mat_file = r"A:\EnclosureProjects\inprep\freemat\code\calibration\WMcalibration\Label3D\labeling_output\20250513_184344_Label3D.mat"
    
    # Path to your base skeleton .mat file (e.g., coco17_skeleton.mat)
    base_skel_file = r"A:\EnclosureProjects\inprep\freemat\code\calibration\WMcalibration\Label3D\skeletons\coco17_skeleton.mat" 
    
    # Desired output path for the COCO JSON file
    coco_json_output_file = r"A:\EnclosureProjects\inprep\freemat\code\calibration\WMcalibration\Label3D\labeling_output\output_coco.json"

    # --- Check if paths exist before running ---
    if not os.path.exists(l3d_mat_file):
        print(f"Error: Label3D .mat file not found at {l3d_mat_file}")
    elif not os.path.exists(base_skel_file):
        print(f"Error: Base skeleton .mat file not found at {base_skel_file}")
    else:
        l3d_to_coco(l3d_mat_file, base_skel_file, coco_json_output_file)