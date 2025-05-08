import json
import os
import numpy as np
from scipy.io import savemat
import sys
import argparse
import pickle

# Tolerance for checking identity/zero pose for reference camera
POSE_TOLERANCE = 1e-6

# --- Helper Functions ---
def get_extrinsics(pose_data, cam_name, ref_cam):
    """
    Extracts the world-to-camera rotation (R_w_cam) and translation (T_w_cam)
    from the pose data dictionary.
    Assumes pose_data contains absolute pose for ref_cam and relative poses
    like 'Cam_XXX_to_ref_cam'.
    """
    if cam_name == ref_cam:
        # Reference camera defines the world origin. Its world-to-camera pose is Identity.
        if ref_cam in pose_data:
            R_w_cam = pose_data[ref_cam]['R']
            T_w_cam = pose_data[ref_cam]['T']
            # Verify it's close to identity/zero for the reference camera
            if not np.allclose(R_w_cam, np.identity(3), atol=1e-6) or \
                not np.allclose(T_w_cam, [0.0, 0.0, 0.0], atol=1e-6):
                print(f"Warning: Pose for reference camera '{ref_cam}' is not identity/zero. Using provided values.")
        else:
            # Assume identity pose if not explicitly defined for ref_cam itself
            print(f"Warning: Explicit pose for reference camera '{ref_cam}' not found. Assuming identity.")
            R_w_cam = [[1.0, 0.0, 0.0], [0.0, 1.0, 0.0], [0.0, 0.0, 1.0]]
            T_w_cam = [0.0, 0.0, 0.0]
    else:
        # Check if the direct world-to-camera pose exists (e.g., for ref_cam itself)
        if cam_name in pose_data:
            print(f"Warning: Found direct pose for non-reference camera '{cam_name}'. Expected relative pose key.")
            R_w_cam = pose_data[cam_name]['R']
            T_w_cam = pose_data[cam_name]['T']
            return R_w_cam, T_w_cam

        # For other cameras, the key 'Cam_XXX_to_ref_cam' contains the world-to-camera pose
        # because ref_cam IS the world origin.
        pose_key = f'{cam_name}_to_{ref_cam}'
        if pose_key not in pose_data:
            raise KeyError(f"Could not find world-to-camera pose key '{pose_key}' in camera_poses dictionary.")
        R_w_cam = pose_data[pose_key]['R']
        T_w_cam = pose_data[pose_key]['T']
    return R_w_cam, T_w_cam

def extract_distortion(dist_coeffs):
    """Extracts RadialDistortion and TangentialDistortion assuming OpenCV order [k1,k2,p1,p2,k3,...]."""
    # --- Add Input Debug Print ---
    print(f"    DEBUG extract_distortion: Received dist_coeffs type={type(dist_coeffs)}")
    try: # Wrap repr in try-except in case it fails for weird objects
        print(f"    DEBUG extract_distortion: Received dist_coeffs value={repr(dist_coeffs)}")
    except Exception:
        print("    DEBUG extract_distortion: Could not get repr() of dist_coeffs value.")
    # --- End Input Debug Print ---

    coeffs = None
    if isinstance(dist_coeffs, np.ndarray):
        coeffs = dist_coeffs.flatten() # Use flattened numpy array directly
    elif isinstance(dist_coeffs, list) and dist_coeffs and isinstance(dist_coeffs[0], list):
        # Handle nested list format from JSON [[coeff1, coeff2, ...]]
        coeffs = np.array(dist_coeffs[0])
    else:
        raise ValueError("Unexpected format for distortion coefficients. Expected flat NumPy array or list-of-lists.")

    # Pad radial distortion k1, k2, k3 with zeros if needed
    k_indices = [0, 1, 4]
    # Check lengths BEFORE indexing
    coeffs_len = len(coeffs)
    k_coeffs_present = [coeffs[i] for i in k_indices if i < coeffs_len]
    RadialDistortion = k_coeffs_present + [0.0] * (len(k_indices) - len(k_coeffs_present))

    # Pad tangential distortion p1, p2 with zeros if needed
    p_indices = [2, 3]
    p_coeffs_present = [coeffs[i] for i in p_indices if i < coeffs_len]
    TangentialDistortion = p_coeffs_present + [0.0] * (len(p_indices) - len(p_coeffs_present))

    if coeffs_len < 2: print(f"Warning: Only {coeffs_len} distortion coefficients. Radial inaccurate.")
    if coeffs_len < 4: print(f"Warning: Fewer than 4 distortion coefficients. Tangential inaccurate.")

    return RadialDistortion, TangentialDistortion

# --- PKL Loading Functions (Copied/Adapted) ---
# (Keep load_multical_workspace_pkl, extract_intrinsics_pkl, extract_extrinsics_pkl here)
def load_multical_workspace_pkl(filepath: str):
    # ... (Implementation from compare_mcal_json_pkl.py)
    """Loads the calibration Workspace object from a .pkl file."""
    print(f"Loading PKL workspace from: {filepath}")
    if not os.path.exists(filepath):
        raise FileNotFoundError(f"Error: File not found at {filepath}")
    try:
        with open(filepath, 'rb') as f:
            workspace = pickle.load(f)
            print(f"Successfully loaded PKL data from {filepath} (type: {type(workspace)})" )
            # Basic validation omitted here for brevity, assume structure is okay
            # Add back if needed:
            # required_attrs = ['point_table', 'names', 'calibrations']
            # ... validation logic ...
            print("PKL Workspace object structure assumed valid.")
            return workspace
    except Exception as e:
        raise RuntimeError(f"An unexpected error occurred loading PKL workspace: {e}")

def extract_intrinsics_pkl(workspace):
    # ... (Implementation from compare_mcal_json_pkl.py)
    """Extracts intrinsics (K, dist, image_size) from the PKL workspace."""
    intrinsics_dict = {}
    try:
        cam_names = list(workspace.names.camera)
        calib_obj = next(iter(workspace.calibrations.values()))
        if len(cam_names) != len(calib_obj.cameras):
             raise ValueError("Mismatch between names and camera calibration objects in PKL.")

        print(f"  DEBUG: Looping through {len(calib_obj.cameras)} PKL camera calibrations...") # DEBUG
        for i, cam_calib in enumerate(calib_obj.cameras):
            cam_name = cam_names[i]
            print(f"    DEBUG: Processing PKL intrinsics for {cam_name}...") # DEBUG
            try:
                K_raw = getattr(cam_calib, 'intrinsic', None)
                dist_raw = getattr(cam_calib, 'dist', None)
                size_raw = getattr(cam_calib, 'image_size', None)
                if K_raw is None or dist_raw is None or size_raw is None:
                     raise AttributeError("Missing intrinsic/dist/image_size attribute")

                print(f"      DEBUG: Raw types - K:{type(K_raw)}, dist:{type(dist_raw)}, size:{type(size_raw)}") # DEBUG
                K = np.array(K_raw)
                dist = np.array(dist_raw)
                img_size = tuple(size_raw)
                print(f"      DEBUG: Converted types - K:{type(K)}, dist:{type(dist)}, size:{type(img_size)}") # DEBUG

                if K.shape == (3,3) and len(img_size) == 2:
                    intrinsics_dict[cam_name] = {'K': K, 'dist': dist.flatten(), 'image_size': img_size}
                else:
                    print(f"    Warning: Invalid data shape for {cam_name} in PKL intrinsics. Skipping.")
            except Exception as e_extract:
                 print(f"    Warning: Could not extract PKL intrinsic params for {cam_name}: {e_extract}. Skipping.")
                 continue
        print(f"Successfully extracted PKL intrinsics for {len(intrinsics_dict)} cameras.")
        return intrinsics_dict
    except Exception as e:
        print(f"Error during PKL intrinsic extraction: {e}")
        return None

def extract_extrinsics_pkl(workspace):
    # ... (Implementation from compare_mcal_json_pkl.py)
    """Extracts world-to-camera extrinsics (R, T) from the PKL workspace."""
    extrinsics_dict = {}
    try:
        cam_names = list(workspace.names.camera)
        calib_obj = next(iter(workspace.calibrations.values()))
        print("  DEBUG: Accessing PKL pose_table.poses...") # DEBUG
        pose_data_raw = calib_obj.camera_poses.pose_table.poses
        print(f"  DEBUG: Raw pose data type: {type(pose_data_raw)}") # DEBUG
        pose_data_array = np.array(pose_data_raw)
        print(f"  DEBUG: Converted pose data type: {type(pose_data_array)}, shape: {pose_data_array.shape}") # DEBUG

        if pose_data_array.ndim != 3 or pose_data_array.shape[1:] != (4, 4):
             raise ValueError(f"Expected pose data shape (N, 4, 4), but got {pose_data_array.shape}")
        if len(cam_names) != pose_data_array.shape[0]:
             raise ValueError(f"Mismatch between names ({len(cam_names)}) and poses ({pose_data_array.shape[0]}) in PKL.")

        print(f"  DEBUG: Looping through {pose_data_array.shape[0]} PKL camera poses...") # DEBUG
        for i, cam_name in enumerate(cam_names):
            print(f"    DEBUG: Processing PKL extrinsics for {cam_name}...") # DEBUG
            try:
                pose_world_to_cam_4x4 = pose_data_array[i]
                R_world_cam = pose_world_to_cam_4x4[:3, :3]
                T_world_cam = pose_world_to_cam_4x4[:3, 3]
                print(f"      DEBUG: Extracted R (shape {R_world_cam.shape}), T (shape {T_world_cam.shape})") # DEBUG

                extrinsics_dict[cam_name] = {'R': R_world_cam, 'T': T_world_cam.flatten()}
            except Exception as e_extract:
                print(f"    Warning: Could not extract PKL extrinsic params for {cam_name}: {e_extract}. Skipping.")
                continue
        print(f"Successfully extracted PKL world-to-camera extrinsics for {len(extrinsics_dict)} cameras.")
        return extrinsics_dict
    except Exception as e:
        print(f"Error during PKL extrinsic extraction: {e}")
        return None

# --- JSON Specific Helper ---
def get_extrinsics_json(pose_data, cam_name, ref_cam):
    """
    Extracts the world-to-camera rotation (R_w_cam) and translation (T_w_cam)
    from the JSON pose data dictionary.
    Assumes pose_data contains absolute pose for ref_cam and relative poses
    like 'Cam_XXX_to_ref_cam'.
    """
    if cam_name == ref_cam:
        if ref_cam in pose_data:
            R_w_cam = pose_data[ref_cam]['R']
            T_w_cam = pose_data[ref_cam]['T']
            if not np.allclose(R_w_cam, np.identity(3), atol=POSE_TOLERANCE) or \
               not np.allclose(T_w_cam, [0.0, 0.0, 0.0], atol=POSE_TOLERANCE):
                print(f"Warning: Pose for reference camera '{ref_cam}' (JSON) is not identity/zero. Using provided values.")
        else:
            print(f"Warning: Explicit pose for reference camera '{ref_cam}' (JSON) not found. Assuming identity.")
            R_w_cam = [[1.0, 0.0, 0.0], [0.0, 1.0, 0.0], [0.0, 0.0, 1.0]]
            T_w_cam = [0.0, 0.0, 0.0]
    else:
        if cam_name in pose_data and '_to_' not in cam_name: # Check for direct pose only if key doesn't indicate relative
            print(f"Warning: Found direct pose for non-reference camera '{cam_name}' in JSON. Expected relative key.")
            R_w_cam = pose_data[cam_name]['R']
            T_w_cam = pose_data[cam_name]['T']
            return R_w_cam, T_w_cam

        pose_key = f'{cam_name}_to_{ref_cam}'
        if pose_key not in pose_data:
            raise KeyError(f"Could not find world-to-camera pose key '{pose_key}' in JSON camera_poses dictionary.")
        R_w_cam = pose_data[pose_key]['R']
        T_w_cam = pose_data[pose_key]['T']
    return R_w_cam, T_w_cam

# --- Main Script ---
def main():
    # --- Argument Parsing ---
    parser = argparse.ArgumentParser(description='Create Label3D compatible .mat calibration files from Multical JSON or PKL output.')
    parser.add_argument('input_path', help='Path to the input calibration file (JSON or PKL). Specify format with --use-pkl if needed.')
    parser.add_argument('output_dir', help='Directory to save the output .mat files.')
    parser.add_argument('--use-pkl', action='store_true', 
                        help='Indicates that the input_path is a Multical workspace PKL file instead of the default JSON.')
    
    args = parser.parse_args()
    
    input_path = args.input_path
    output_dir = args.output_dir
    use_pkl = args.use_pkl

    print(f"Input path: {input_path}")
    print(f"Output directory: {output_dir}")
    print(f"Using PKL input: {use_pkl}")

    if not os.path.exists(input_path):
        print(f"Error: Input file not found at {input_path}")
        return

    # --- Data Loading and Preparation ---
    target_cameras = []
    all_intrinsics = {}
    all_extrinsics = {}
    json_data = None # Keep json data if loaded for reference

    try:
        if use_pkl:
            # Load from PKL
            print("--- Loading data from PKL file ---")
            workspace = load_multical_workspace_pkl(input_path)
            if not workspace:
                 return # Error handled in loader
            all_intrinsics = extract_intrinsics_pkl(workspace)
            all_extrinsics = extract_extrinsics_pkl(workspace)
            if not all_intrinsics or not all_extrinsics:
                 print("Error extracting data from PKL workspace.")
                 return
            target_cameras = sorted(list(workspace.names.camera))
            print(f"Found {len(target_cameras)} cameras in PKL workspace.")

        else:
            # Load from JSON (default)
            print("--- Loading data from JSON file ---")
            with open(input_path, 'r') as f:
                json_data = json.load(f)

            # Auto-detect Reference Camera from JSON
            detected_ref_cam = None
            if 'camera_poses' in json_data:
                print("Attempting to auto-detect reference camera from JSON...")
                for pose_key, pose_info in json_data['camera_poses'].items():
                    print(f"  DEBUG: Checking JSON pose key: {pose_key}") # DEBUG
                    if '_to_' not in pose_key:
                        print(f"    DEBUG: Potential reference key: {pose_key}") # DEBUG
                        try:
                            R = np.array(pose_info['R'])
                            T = np.array(pose_info['T'])
                            print(f"      DEBUG: R type {type(R)}, T type {type(T)}") # DEBUG
                            # --- Add check here BEFORE np.allclose --- 
                            if not isinstance(R, np.ndarray) or not isinstance(T, np.ndarray):
                                print("      DEBUG: R or T is not a NumPy array after conversion. Skipping np.allclose.")
                                continue
                                
                            is_identity_R = np.allclose(R, np.identity(3), atol=POSE_TOLERANCE)
                            is_zero_T = np.allclose(T, [0.0, 0.0, 0.0], atol=POSE_TOLERANCE)
                            print(f"      DEBUG: is_identity_R={is_identity_R}, is_zero_T={is_zero_T}") # DEBUG

                            if is_identity_R and is_zero_T:
                                detected_ref_cam = pose_key
                                print(f"  Reference camera detected: {detected_ref_cam}")
                                break
                        except Exception as e_ref_check:
                            print(f"    DEBUG: Error checking potential ref key {pose_key}: {e_ref_check}") # DEBUG
                            continue
            
            if detected_ref_cam is None:
                print("Error: Could not auto-detect reference camera in JSON 'camera_poses'.")
                return

            # Validate JSON Structure
            if 'cameras' not in json_data or 'camera_poses' not in json_data:
                print("Error: JSON file missing required 'cameras' or 'camera_poses' keys.")
                return

            all_intrinsics = json_data['cameras']
            # Note: all_extrinsics is not directly populated here, 
            # we use get_extrinsics_json inside the loop for JSON.
            target_cameras = sorted(list(all_intrinsics.keys()))
            print(f"Found {len(target_cameras)} cameras in JSON intrinsics.")

    except FileNotFoundError:
        print(f"Error: Input file not found at {input_path}") # Should be caught earlier, but defensive
        return
    except (json.JSONDecodeError, pickle.UnpicklingError, ValueError, AttributeError, RuntimeError, KeyError) as e:
        print(f"Error during data loading or initial processing: {e}")
        return
    except Exception as e:
        print(f"An unexpected error occurred during loading: {e}")
        return

    if not target_cameras:
        print("Error: No target cameras identified from the input source.")
        return

    # --- Create Output Directory ---
    # (Moved down to ensure data loading worked first)
    if not os.path.exists(output_dir):
        print(f"Creating output directory: {output_dir}")
        os.makedirs(output_dir)
    else:
        print(f"Output directory already exists: {output_dir}")

    # --- Process Target Cameras ---
    print(f"\n--- Processing {len(target_cameras)} Cameras ---")
    processed_count = 0
    for cam_name in target_cameras:
        print(f"Processing {cam_name}...")

        try:
            # Get Intrinsics for this camera
            if cam_name not in all_intrinsics:
                 print(f"Error: Intrinsic data for {cam_name} not found. Skipping.")
                 continue
            intrinsics = all_intrinsics[cam_name]
            K_original = intrinsics['K']
            dist_coeffs = intrinsics['dist'] # Will be array for PKL, list-of-list for JSON
            img_size = intrinsics['image_size']
            RDistort, TDistort = extract_distortion(dist_coeffs)

            # Get Extrinsics (World-to-Camera) for this camera
            if use_pkl:
                if cam_name not in all_extrinsics:
                    print(f"Error: Extrinsic data for {cam_name} not found in PKL data. Skipping.")
                    continue
                extrinsics = all_extrinsics[cam_name]
                R_w_cam = extrinsics['R']
                T_w_cam = extrinsics['T']
            else: # Use JSON
                # We need json_data and detected_ref_cam from the loading block
                if json_data is None or detected_ref_cam is None:
                     print("Internal Error: JSON data or reference camera not available for extrinsic lookup. Skipping.")
                     continue
                R_w_cam, T_w_cam = get_extrinsics_json(json_data['camera_poses'], cam_name, detected_ref_cam)

            # --- Add Debug Prints Here ---
            print(f"  DEBUG {cam_name}: Types before np.array conversion:")
            print(f"    K_original: {type(K_original)}")
            print(f"    dist_coeffs: {type(dist_coeffs)}")
            print(f"    img_size: {type(img_size)}")
            print(f"    RDistort: {type(RDistort)}")
            print(f"    TDistort: {type(TDistort)}")
            print(f"    R_w_cam: {type(R_w_cam)}")
            print(f"    T_w_cam: {type(T_w_cam)}")
            # Optionally print shapes/values if needed later
            # print(f"    dist_coeffs value: {dist_coeffs}")
            # print(f"    R_w_cam shape: {getattr(R_w_cam, 'shape', 'N/A')}")
            # print(f"    T_w_cam shape: {getattr(T_w_cam, 'shape', 'N/A')}")
            # --- End Debug Prints ---

            # --- Prepare Data for .mat file ---
            K_np_original = np.asarray(K_original, dtype=np.float64)
            R_w_cam_np    = np.asarray(R_w_cam,  dtype=np.float64) # Input R_w_c
            T_w_cam_np    = np.asarray(T_w_cam,  dtype=np.float64) # Input T_w_c (METERS)

            # r: R_c_w (Camera-to-World Rotation)
            r_final_for_mat = R_w_cam_np.T

            # t: T_w_c_row (World origin in Cam Coords, 1x3 Row Vector, in MILLIMETERS)
            # Ensure T_w_cam_np is treated as a column vector first for scaling, then transpose to row.
            T_w_cam_col_m = T_w_cam_np.reshape(3, 1) # Ensure column for scaling
            T_w_cam_col_mm = T_w_cam_col_m * 1000.0
            t_final_for_mat_mm_row = T_w_cam_col_mm.T # Transpose to 1x3 row

            # --- Convert K to the non-standard layout that Label3D expects (cx,cy in bottom row) ---
            fx, fy = K_np_original[0, 0], K_np_original[1, 1]
            cx, cy = K_np_original[0, 2], K_np_original[1, 2]
            K_label3d = np.array([[fx, 0, 0],
                                  [0,  fy, 0],
                                  [cx, cy, 1]], dtype=np.float64)

            mat_dict = dict(
                K        = K_label3d,
                r        = r_final_for_mat,            # R_c_w
                t        = t_final_for_mat_mm_row,     # T_w_c_row in mm (1x3)
                RDistort = np.asarray(RDistort).reshape(-1, 1),
                TDistort = np.asarray(TDistort).reshape(-1, 1),
                image_size = np.array(img_size),
            )
            
            # --- Save .mat File ---
            mat_filename = f"{cam_name}_params.mat"
            mat_filepath = os.path.join(output_dir, mat_filename)
            
            # When saving with savemat, a (3,1) array for 't' should be saved as such.
            # The oned_as='row' primarily affects 1D arrays (e.g., shape (3,)).
            # For a 2D array like (3,1), its shape should be preserved.
            # CORRECTED: oned_as='row' IS helpful here to ensure the 1x3 vector for t is saved correctly.
            savemat(mat_filepath, mat_dict, do_compression=False, oned_as='row')
            print(f"  Successfully saved: {mat_filepath}")
            processed_count += 1

        except (KeyError, ValueError, IndexError, TypeError) as e:
            print(f"Error processing data for {cam_name}: {e}. Skipping.")
            continue
        except Exception as e:
            print(f"An unexpected error occurred processing {cam_name}: {e}. Skipping.")
            continue

    print(f"\nFinished processing. Saved {processed_count} / {len(target_cameras)} camera parameter files to '{output_dir}'.")

if __name__ == "__main__":
    main() 