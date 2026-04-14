function wipe_dataset(basePath)
% WIPE_DATASET_SAFE Safely clears specific dataset subfolders
% Requires confirmation BEFORE wiping each folder

    % ---- Whitelisted folders ----
    allowedFolders = {
        'dataset/blfiles'
        'dataset/cpfiles'
        'dataset/cstfiles'
        'dataset/polarfiles'
        'dataset/coordinates'
    };

    % ---- Base path checks ----
    if ~isfolder(basePath)
        error('Base path does not exist.');
    end

    if length(basePath) < 10
        error('Base path suspiciously short. Aborting.');
    end

    fprintf('Safe dataset wipe initialized.\n\n');

    % ---- Loop through folders ----
    for i = 1:length(allowedFolders)
        folder = fullfile(basePath, allowedFolders{i});

        if ~isfolder(folder)
            warning('Skipping missing folder: %s\n', folder);
            continue;
        end

        fprintf('\n-----------------------------------\n');
        fprintf('Target folder:\n%s\n', folder);

        % Show contents before deleting
        files = dir(folder);
        files = files(~ismember({files.name}, {'.','..'}));

        if isempty(files)
            fprintf('Folder already empty. Skipping.\n');
            continue;
        end

        fprintf('Contains %d items.\n', length(files));

        % ---- Per-folder confirmation ----
        prompt = sprintf('Type YES to wipe this folder, or press Enter to skip: ');
        confirm = input(prompt, 's');

        if ~strcmp(confirm, 'YES')
            fprintf('Skipped: %s\n', folder);
            continue;
        end

        % ---- Delete contents ----
        for j = 1:length(files)
            fullItem = fullfile(folder, files(j).name);

            try
                if files(j).isdir
                    rmdir(fullItem, 's');
                else
                    delete(fullItem);
                end
            catch ME
                warning('Failed to delete: %s\n%s', fullItem, ME.message);
            end
        end

        fprintf('Wiped: %s\n', folder);
    end

    fprintf('\nDone. Only confirmed folders were modified.\n');
end