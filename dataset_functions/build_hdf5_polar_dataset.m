function build_hdf5_polar_dataset(output_file)

    polar_dir = 'dataset/polarfiles/';
    cst_dir   = 'dataset/cstfiles/';

    polar_files = dir(fullfile(polar_dir, '*.txt'));
    num_files = length(polar_files);

    % --- OPTIMIZATION: Pre-allocate cell arrays ---
    X_cell = cell(num_files, 1);
    Y_cell = cell(num_files, 1);

    for i = 1:num_files

        polar_path = fullfile(polar_dir, polar_files(i).name);

        % Match CST file (same name assumed)
        [~, polar_name, ~] = fileparts(polar_files(i).name);
        name = erase(polar_name, "polar_");
        cst_name = sprintf("cst_%s.txt", name);
        cst_path = fullfile(cst_dir, cst_name);

        if ~isfile(cst_path)
            warning('Missing CST file for %s', polar_name);
            continue;
        end

        % 1. Read CST
        CST = readmatrix(cst_path);
        if numel(CST) ~= 16
            warning('Invalid CST size in %s', cst_name);
            continue;
        end
        CST = CST(:).'; 

        % 2. Read polar file
        fid = fopen(polar_path, 'r');
        if fid == -1
            warning('Could not open %s', polar_path);
            continue;
        end

        Re = NaN;
        data = [];
        in_data_block = false;

        while ~feof(fid)
            line = fgetl(fid);
            if ~ischar(line), break; end
        
            if contains(lower(line), 'alpha') && contains(lower(line), 'cl')
                in_data_block = true;
                line2 = fgetl(fid);
                if ischar(line2) && isempty(regexp(line2, '^-', 'once'))
                    nums = sscanf(line2, '%f');
                    if numel(nums) == 7, data = [data; nums(:).']; end
                end
                continue;
            end
        
            if ~in_data_block
                if contains(line, 'Re =')
                    tokens = regexp(line, 'Re\s*=\s*([\d\.]+)\s*e\s*([\d\+\-]+)', 'tokens');
                    if ~isempty(tokens)
                        base = str2double(tokens{1}{1});
                        expn = str2double(tokens{1}{2});
                        Re = base * 10^expn;
                    end
                end
                continue;
            end
        
            nums = sscanf(line, '%f');
            if numel(nums) == 7
                data = [data; nums(:).'];
            end
        end
        fclose(fid);

        if isempty(data) || isnan(Re)
            warning('Invalid polar data in %s', polar_name);
            continue;
        end

        % 3. Build X and Y for THIS file
        alpha = data(:,1);
        n = length(alpha);
        Re_log = log10(Re);

        % --- Store in cell arrays instead of appending ---
        X_cell{i} = [repmat(CST, n, 1), repmat(Re_log, n, 1), alpha];
        Y_cell{i} = data(:, 2:6); % CL, CD, CDp, CM, Xtr_top

        fprintf('Processed %s (%d points)\n', polar_name, n);
    end

    % --- OPTIMIZATION: Concatenate all data at once ---
    % Remove empty cells (in case some files were skipped)
    X_cell = X_cell(~cellfun(@isempty, X_cell));
    Y_cell = Y_cell(~cellfun(@isempty, Y_cell));

    X_all = vertcat(X_cell{:});
    Y_all = vertcat(Y_cell{:});

    % 4. Write HDF5 (unchanged logic)
    if isfile(output_file), delete(output_file); end

    szX = size(X_all);
    chunkX = [min(1024, szX(1)), szX(2)];
    h5create(output_file, '/X', szX, 'ChunkSize', chunkX);
    h5write(output_file, '/X', X_all);

    szY = size(Y_all);
    chunkY = [min(1024, szY(1)), szY(2)];
    h5create(output_file, '/Y', szY, 'ChunkSize', chunkY);
    h5write(output_file, '/Y', Y_all);

    h5writeatt(output_file, '/', 'description', ...
        'X = [CST(16), log10(Re), alpha], Y = [CL, CD, CDp, CM, Top_Xtr]');

    fprintf('\nDataset saved: %s\n', output_file);
    fprintf('Total samples: %d\n', size(X_all,1));
end