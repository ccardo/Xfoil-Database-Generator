function n_saved = fetch_selig_airfoils(n_airfoils, varargin)
% FETCH_SELIG_AIRFOILS  Download the UIUC/Selig airfoil coordinate database
%                       and store N randomly selected airfoils as numbered,
%                       XFOIL-readable coordinate files.
%
% USAGE
%   n_saved = fetch_selig_airfoils(n_airfoils)
%   n_saved = fetch_selig_airfoils(n_airfoils, Name, Value, ...)
%
% REQUIRED INPUT
%   n_airfoils     - Number of airfoils to store (e.g. 500 or 10000).
%                    The Selig database contains ~1,650 unique airfoils.
%                    If n_airfoils ≤ total valid airfoils: a random subset
%                    is selected (without replacement).
%                    If n_airfoils >  total valid airfoils: all valid
%                    airfoils are stored and a warning is issued.
%
% OPTIONAL NAME-VALUE PAIRS
%   'output_dir'     - Destination folder for the numbered .dat files.
%                      Default: 'dataset/coordinates'
%   'cache_dir'      - Folder where the downloaded zip and raw files are
%                      kept between calls. Default: 'dataset/selig_cache'
%   'force_download' - Re-download the zip even if already cached.
%                      Default: false
%   'rng_seed'       - Integer seed for the random selection, for
%                      reproducibility. Default: [] (use current RNG state)
%   'verbose'        - Print progress to the command window. Default: true
%
% OUTPUT
%   n_saved  - Number of airfoil files actually written.
%
% OUTPUT FILE FORMAT
%   Files are named  00000.dat, 00001.dat, … (zero-padded, 0-based index).
%   Format is the Selig / XFOIL convention:
%     Line 1  : "Airfoil <index>"   (anonymous — no original name)
%     Lines 2+: "  x   y"  pairs,  TE → LE → TE  (counterclockwise)
%   Coordinates are normalised to chord = 1, x ∈ [0, 1].
%
% DATA SOURCE
%   UIUC Airfoil Coordinates Database (M. Selig, UIUC Applied Aerodynamics)
%   https://m-selig.ae.illinois.edu/ads/coord_database.html
%   The zip archive (~4 MB) is downloaded once and cached in 'cache_dir'.
%
% EXAMPLE
%   fetch_selig_airfoils(200)
%   fetch_selig_airfoils(1000, 'output_dir', 'my_foils', 'rng_seed', 42)

    % ------------------------------------------------------------------ %
    %  1. Parse & validate inputs                                          %
    % ------------------------------------------------------------------ %
    if nargin < 1
        error('fetch_selig_airfoils: n_airfoils is required. Usage: fetch_selig_airfoils(N)');
    end
    if ~isnumeric(n_airfoils) || ~isscalar(n_airfoils) || n_airfoils < 1
        error('fetch_selig_airfoils: n_airfoils must be a positive integer.');
    end
    n_airfoils = round(n_airfoils);

    p = inputParser();
    addParameter(p, 'output_dir',     'dataset/coordinates',  @(x) ischar(x)||isstring(x));
    addParameter(p, 'cache_dir',      'dataset/!selig_cache', @(x) ischar(x)||isstring(x));
    addParameter(p, 'force_download', false,                  @(x) islogical(x)||isnumeric(x));
    addParameter(p, 'rng_seed',       [],                     @(x) isempty(x)||(isnumeric(x)&&isscalar(x)));
    addParameter(p, 'verbose',        true,                   @(x) islogical(x)||isnumeric(x));
    parse(p, varargin{:});
    r = p.Results;

    output_dir     = char(r.output_dir);
    cache_dir      = char(r.cache_dir);
    force_download = logical(r.force_download);
    verbose        = logical(r.verbose);

    ZIP_URL  = 'https://m-selig.ae.illinois.edu/ads/archives/coord_seligFmt.zip';
    ZIP_FILE = fullfile(cache_dir, 'coord_seligFmt.zip');
    RAW_DIR  = fullfile(cache_dir, 'coord_seligFmt');

    % ------------------------------------------------------------------ %
    %  2. Create folders                                                   %
    % ------------------------------------------------------------------ %
    ensure_dir(cache_dir);
    ensure_dir(output_dir);

    % ------------------------------------------------------------------ %
    %  3. Download zip (once, unless forced)                               %
    % ------------------------------------------------------------------ %
    if force_download || ~isfile(ZIP_FILE)
        vprint(verbose, 'Downloading Selig database zip (~4 MB) …\n');
        try
            websave(ZIP_FILE, ZIP_URL);
            vprint(verbose, 'Download complete: %s\n', ZIP_FILE);
        catch ME
            error('fetch_selig_airfoils: download failed.\n  URL : %s\n  Error: %s', ...
                  ZIP_URL, ME.message);
        end
    else
        vprint(verbose, 'Using cached zip: %s\n', ZIP_FILE);
    end

    % ------------------------------------------------------------------ %
    %  4. Extract zip (skip if already extracted and not forced)           %
    % ------------------------------------------------------------------ %
    if force_download || ~isfolder(RAW_DIR)
        vprint(verbose, 'Extracting zip …\n');
        unzip(ZIP_FILE, cache_dir);
        vprint(verbose, 'Extraction complete → %s\n', RAW_DIR);
    else
        vprint(verbose, 'Using cached extraction: %s\n', RAW_DIR);
    end

    % ------------------------------------------------------------------ %
    %  5. Collect all .dat files                                           %
    % ------------------------------------------------------------------ %
    listing = [dir(fullfile(RAW_DIR, '*.dat')); ...
               dir(fullfile(RAW_DIR, '*.DAT'))];

    if isempty(listing)
        % Some zips extract into a sub-subfolder — try one level deeper
        sub = dir(RAW_DIR);
        for k = 1:numel(sub)
            if sub(k).isdir && ~startsWith(sub(k).name, '.')
                listing = [listing; ...
                           dir(fullfile(RAW_DIR, sub(k).name, '*.dat')); ...
                           dir(fullfile(RAW_DIR, sub(k).name, '*.DAT'))]; %#ok<AGROW>
            end
        end
    end

    if isempty(listing)
        error('fetch_selig_airfoils: no .dat files found under %s', RAW_DIR);
    end

    n_raw = numel(listing);
    vprint(verbose, 'Found %d raw .dat files in the database.\n', n_raw);

    % Shuffle the file list so the validity pass itself is randomised
    if ~isempty(r.rng_seed)
        rng(r.rng_seed);
    end
    listing = listing(randperm(n_raw));

    % ------------------------------------------------------------------ %
    %  6. Parse, validate, and write                                       %
    % ------------------------------------------------------------------ %
    n_skipped = 0;
    target    = min(n_airfoils, n_raw);   % can't exceed what exists

    if n_airfoils > n_raw
        warning('fetch_selig_airfoils:tooFewAirfoils', ...
            ['Requested %d airfoils but the database contains only %d files.\n' ...
             'Storing all valid airfoils found.'], n_airfoils, n_raw);
    end

    % Find the next available index by counting files already in output_dir.
    % This way repeated calls always continue numbering from where they left
    % off and never overwrite previously saved files.
    existing   = dir(fullfile(output_dir, '*.dat'));
    next_index = numel(existing);   % 0-based: 3 files exist -> next is 00003
    n_saved    = 0;                 % count written in THIS call

    vprint(verbose, 'Processing files (target: %d, starting index: %05d) ...\n', ...
           target, next_index);

    for k = 1:n_raw
        if n_saved >= target
            break;
        end

        raw_path = fullfile(listing(k).folder, listing(k).name);
        [x, y, ok] = parse_selig_dat(raw_path);

        if ~ok
            n_skipped = n_skipped + 1;
            continue;
        end

        % Derive padded name from next_index
        filename = sprintf('%05d', next_index);
        out_path = fullfile(output_dir, [filename '.dat']);

        % Create per-airfoil Cp and Cf subdirectories
        ensure_dir(fullfile('dataset', 'cpfiles', filename));
        ensure_dir(fullfile('dataset', 'blfiles', filename));

        write_xfoil_dat(out_path, listing(k).name(1:end-4), x, y, next_index);

        next_index = next_index + 1;
        n_saved    = n_saved    + 1;

        if verbose && mod(n_saved, 100) == 0
            fprintf('  ... saved %d / %d\n', n_saved, target);
        end
    end

    % ------------------------------------------------------------------ %
    %  7. Report                                                           %
    % ------------------------------------------------------------------ %
    vprint(verbose, '\n=== fetch_selig_airfoils complete ===\n');
    vprint(verbose, '  Saved   : %d airfoil files → %s\n', n_saved, output_dir);
    vprint(verbose, '  Skipped : %d files (invalid / degenerate geometry)\n', n_skipped);
    if n_saved < n_airfoils
        vprint(verbose, '  Note    : fewer airfoils saved than requested (%d < %d).\n', ...
               n_saved, n_airfoils);
    end
end


% ========================================================================
%  LOCAL FUNCTION: parse a Selig-format .dat file
% ========================================================================
function [x, y, ok] = parse_selig_dat(filepath)
% Reads a Selig .dat file and returns validated, normalised coordinates.
% ok = false if the file is malformed or the geometry is degenerate.

    ok = false;
    x  = [];
    y  = [];

    MIN_POINTS = 20;   % fewer than this → skip

    % -- Read file lines -------------------------------------------------
    try
        fid = fopen(filepath, 'r');
        if fid == -1; return; end
        raw_lines = {};
        while ~feof(fid)
            raw_lines{end+1} = fgetl(fid); %#ok<AGROW>
        end
        fclose(fid);
    catch
        return;
    end

    % -- Strip comment lines (starting with #) and the header line -------
    data_lines = {};
    skipped_header = false;
    for i = 1:numel(raw_lines)
        line = strtrim(raw_lines{i});
        if isempty(line);                    continue; end
        if startsWith(line, '#');            continue; end  % UIUC comment
        % Skip the first non-comment, non-numeric line (airfoil name header)
        nums = sscanf(line, '%f %f');
        if numel(nums) < 2
            if ~skipped_header
                skipped_header = true;
                continue;   % this is the name/header line
            else
                continue;   % extra non-numeric line — ignore
            end
        end
        data_lines{end+1} = line; %#ok<AGROW>
    end

    if numel(data_lines) < MIN_POINTS; return; end

    % -- Parse coordinate pairs ------------------------------------------
    coords = zeros(numel(data_lines), 2);
    n_ok   = 0;
    for i = 1:numel(data_lines)
        nums = sscanf(data_lines{i}, '%f %f');
        if numel(nums) >= 2
            n_ok = n_ok + 1;
            coords(n_ok, :) = nums(1:2)';
        end
    end
    coords = coords(1:n_ok, :);

    if n_ok < MIN_POINTS; return; end

    x_raw = coords(:, 1);
    y_raw = coords(:, 2);

    % -- Detect and handle Lednicer format (two separate surfaces) -------
    % Lednicer files start with a line giving nUpper nLower counts.
    % Heuristic: first "x" value is a non-integer count-like number (e.g. 35.0)
    % and the second x value restarts near 0. We detect by checking whether
    % the data appears to have a repeated x=0 mid-way through.
    zero_crossings = find(x_raw(2:end) < 0.01 & x_raw(1:end-1) > 0.5);
    if ~isempty(zero_crossings)
        % Likely Lednicer: split at the interior near-zero x, reverse
        % upper surface so the full wrap is TE→LE→TE
        split = zero_crossings(1) + 1;
        x_upper = flipud(x_raw(1:split-1));
        y_upper = flipud(y_raw(1:split-1));
        x_lower = x_raw(split:end);
        y_lower = y_raw(split:end);
        x_raw   = [x_upper; x_lower];
        y_raw   = [y_upper; y_lower];
    end

    % -- Normalise chord to [0, 1] ---------------------------------------
    x_min = min(x_raw);
    x_max = max(x_raw);
    chord = x_max - x_min;
    if chord < 1e-6; return; end    % degenerate
    x_norm = (x_raw - x_min) / chord;
    y_norm =  y_raw          / chord;

    % -- Sanity checks ---------------------------------------------------
    % 1. Must span at least 80 % of chord
    if (max(x_norm) - min(x_norm)) < 0.8; return; end

    % 2. Must have both positive and negative (or near-zero) y extent
    %    → rules out flat plates stored as single surface
    if max(y_norm) < 0.001; return; end

    % 3. No NaN / Inf
    if any(~isfinite(x_norm)) || any(~isfinite(y_norm)); return; end

    % 4. Must start and end near the trailing edge (x ≈ 1)
    if x_norm(1) < 0.5 || x_norm(end) < 0.5; return; end

    x  = x_norm;
    y  = y_norm;
    ok = true;
end


% ========================================================================
%  LOCAL FUNCTION: write XFOIL-readable .dat file
% ========================================================================
function write_xfoil_dat(filepath, name, x, y, index)
    fid = fopen(filepath, 'w');
    if fid == -1
        error('fetch_selig_airfoils: cannot write to %s', filepath);
    end
    fprintf(fid, 'Airfoil %d %s\r\n', index, name);   % XFOIL expects a name on line 1
    for k = 1:numel(x)
        fprintf(fid, '  %.6f  %.6f\r\n', x(k), y(k));
    end
    fclose(fid);
end


% ========================================================================
%  LOCAL FUNCTION: create a folder (including parents) if needed
% ========================================================================
function ensure_dir(d)
    if ~isfolder(d)
        [ok, msg] = mkdir(d);
        if ~ok
            error('fetch_selig_airfoils: could not create folder %s\n  %s', d, msg);
        end
    end
end


% ========================================================================
%  LOCAL FUNCTION: conditional fprintf
% ========================================================================
function vprint(verbose, fmt, varargin)
    if verbose
        fprintf(fmt, varargin{:});
    end
end