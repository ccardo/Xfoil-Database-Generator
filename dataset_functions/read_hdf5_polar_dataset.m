function [X, Y, desc] = read_hdf5_polar_dataset(input_file)
    % READ_HDF5_POLAR_DATASET Reads the airfoil dataset from an H5 file.
    %
    % Usage:
    %   [X, Y, desc] = read_hdf5_polar_dataset('test_dataset.h5');

    if ~isfile(input_file)
        error('File %s not found.', input_file);
    end

    % 1. Read the main datasets
    % Note: h5read automatically handles the dimensions defined in h5create
    X = h5read(input_file, '/X');
    Y = h5read(input_file, '/Y');

    % 2. Read the description attribute (optional but helpful)
    try
        desc = h5readatt(input_file, '/', 'description');
    catch
        desc = 'No description found.';
    end

    fprintf('Dataset loaded from: %s\n', input_file);
    fprintf('Dimensions: X %dx%d, Y %dx%d\n', size(X,1), size(X,2), size(Y,1), size(Y,2));
end