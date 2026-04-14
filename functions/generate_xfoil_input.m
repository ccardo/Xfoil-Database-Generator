function generate_xfoil_input(geom_file, varargin)
% GENERATE_XFOIL_INPUT  Auto-generate an XFOIL batch input script.
%
% USAGE
%   generate_xfoil_input(geom_file, Re, 'alpha',       alpha_value)
%   generate_xfoil_input(geom_file, Re, 'cl',          cl_value)
%   generate_xfoil_input(geom_file, Re, 'alpha_range', [alpha_start, alpha_end, alpha_step])
%
% INPUTS
%   geom_file  - Path to the airfoil coordinate file (Selig or Lednicer format)

%
% OPTIONAL NAME-VALUE PAIRS (mutually exclusive — supply exactly one)
%   'background'   - Do not open pxplot.exe or pplot.exe (default = true)
%   'reynolds'     - Reynolds number (default = 1e6)
%   'alpha'        - Single angle of attack in degrees
%   'cl'           - Single target lift coefficient 
%   'alpha_range'  - Alpha sweep as [alpha_start, alpha_end, alpha_step] (degrees)
%                    e.g. [-5, 15, 0.5] sweeps from -5° to +15° in 0.5° steps.
%                    In range mode, Cp and Cf are written per angle of attack
%                    (cp_<alpha>.txt, cf_<alpha>.txt); the polar accumulates
%                    all points into a single polar.txt.
%
% OUTPUT FILES (written to the current folder)
%   xfoil_input.txt        – XFOIL batch script
%   polar.txt              – Polar table (all operating points)
%
%   Single-point modes ('alpha' or 'cl'):
%     cp.txt               – Cp distribution
%     cf.txt               – Cf distribution
%
%   Range mode ('alpha_range'):
%     cp_<alpha>.txt       – Cp distribution at each angle (e.g. cp_5.00.txt)
%     cf_<alpha>.txt       – Cf distribution at each angle (e.g. cf_5.00.txt)
%
% EXAMPLES
%   generate_xfoil_input('naca2412.dat', 1e6, 'alpha', 5)
%   generate_xfoil_input('naca2412.dat', 1e6, 'cl', 0.8)
%   generate_xfoil_input('naca2412.dat', 1e6, 'alpha_range', [-5, 15, 0.5])
%
%   Then run:  xfoil < xfoil_input.txt        (Linux / macOS)
%              xfoil.exe < xfoil_input.txt    (Windows)

    % ------------------------------------------------------------------ %
    %  1. Parse & validate inputs                                          %
    % ------------------------------------------------------------------ %
    if nargin < 2
        error('generate_xfoil_input: at least two arguments required.');
    end

    p = inputParser();
    addRequired(p,  'geom_file',   @(x) ischar(x) || isstring(x));
    addParameter(p, 'show_plots',  true, @(x) islogical(x) && isscalar(x));
    addParameter(p, 'reynolds',    1e6,  @(x) isnumeric(x) && isscalar(x) && x > 0);
    addParameter(p, 'alpha',       [],   @(x) isnumeric(x) && isscalar(x));
    addParameter(p, 'cl',          [],   @(x) isnumeric(x) && isscalar(x));
    addParameter(p, 'alpha_range', [],   @(x) isnumeric(x) && numel(x) == 3);
    parse(p, geom_file, varargin{:});
    
    show_plots  = p.Results.show_plots;
    Re          = p.Results.reynolds;
    alpha_val   = p.Results.alpha;
    cl_val      = p.Results.cl;
    alpha_range = p.Results.alpha_range;

    % Exactly one operating-point mode must be specified
    n_modes = (~isempty(alpha_val)) + (~isempty(cl_val)) + (~isempty(alpha_range));
    if n_modes > 1
        error('generate_xfoil_input: specify only one of ''alpha'', ''cl'', or ''alpha_range''.');
    end
    if n_modes == 0
        error('generate_xfoil_input: specify one of ''alpha'', ''cl'', or ''alpha_range''.');
    end

    % Validate alpha_range
    if ~isempty(alpha_range)
        a_start = alpha_range(1);
        a_end   = alpha_range(2);
        a_step  = alpha_range(3);
        if a_step == 0
            error('generate_xfoil_input: alpha_range step must be non-zero.');
        end
        if (a_end - a_start) * a_step < 0
            error('generate_xfoil_input: alpha_range step sign inconsistent with start→end direction.');
        end
        % Build the explicit alpha vector (for reporting and file naming)
        alpha_vec = a_start : a_step : a_end;
        if isempty(alpha_vec)
            error('generate_xfoil_input: alpha_range produces an empty sweep.');
        end
    end

    geom_file = char(geom_file);
    if ~isfile(geom_file)
        error('generate_xfoil_input: geometry file not found: %s', geom_file);
    end

    % ------------------------------------------------------------------ %
    %  2. Fixed settings                                                   %
    % ------------------------------------------------------------------ %
    N_PANELS    = 300;
    OUTPUT_DIR  = '.';
    POLAR_FILE  = fullfile(OUTPUT_DIR, sprintf('polar_%s.txt', geom_file(1:end-4)));
    SCRIPT_FILE = 'xfoil_input.txt';

    % ------------------------------------------------------------------ %
    %  3. Build the XFOIL command sequence                                 %
    % ------------------------------------------------------------------ %
    lines = {};

    % -- Load geometry -------------------------------------------------
    lines{end+1} = sprintf('LOAD %s', geom_file);
    lines{end+1} = '';                              % accept default airfoil name

    lines{end+1} = 'PANE';
    lines{end+1} = '';

    if ~show_plots
        lines{end+1} = 'PLOP';
        lines{end+1} = 'G F';
        lines{end+1} = '';
    end

    % -- Panel discretisation ------------------------------------------
    lines{end+1} = 'PPAR';
    lines{end+1} = sprintf('N %d', N_PANELS);
    lines{end+1} = '';                              % confirm & stay in PPAR
    lines{end+1} = '';                              % exit PPAR to top-level

    % -- Enter OPER menu -----------------------------------------------
    lines{end+1} = 'OPER';

    % -- Viscous mode + Reynolds number --------------------------------
    lines{end+1} = sprintf('VISC %g', Re);

    % -- Iteration limit -----------------------------------------------
    lines{end+1} = 'ITER 300';

    % ------------------------------------------------------------------ %
    %  Branch A : single alpha                                             %
    % ------------------------------------------------------------------ %
    if ~isempty(alpha_val)
        CP_FILE = fullfile(OUTPUT_DIR, sprintf('cp_a%+07.2f.txt', alpha_val));
        BL_FILE = fullfile(OUTPUT_DIR, sprintf('bl_a%+07.2f.txt', alpha_val));

        lines{end+1} = sprintf('ALFA %g', alpha_val);

        lines{end+1} = 'CPWR';
        lines{end+1} = CP_FILE;

        lines{end+1} = 'DUMP';
        lines{end+1} = BL_FILE;

        % One-point polar via PACC
        lines{end+1} = 'PACC';
        lines{end+1} = POLAR_FILE;
        lines{end+1} = '';                          % no dump file
        lines{end+1} = sprintf('ALFA %g', alpha_val);
        lines{end+1} = 'PACC';                     % toggle off

    % ------------------------------------------------------------------ %
    %  Branch B : single Cl                                                %
    % ------------------------------------------------------------------ %
    elseif ~isempty(cl_val)
        CP_FILE = fullfile(OUTPUT_DIR, sprintf('cp_cl%+07.2f.txt', cl_val));
        BL_FILE = fullfile(OUTPUT_DIR, sprintf('bl_cl%+07.2f.txt', cl_val));

        lines{end+1} = sprintf('CL %g', cl_val);

        lines{end+1} = 'CPWR';
        lines{end+1} = CP_FILE;

        lines{end+1} = 'DUMP';
        lines{end+1} = BL_FILE;

        % One-point polar via PACC
        lines{end+1} = 'PACC';
        lines{end+1} = POLAR_FILE;
        lines{end+1} = '';
        lines{end+1} = sprintf('CL %g', cl_val);
        lines{end+1} = 'PACC';

    % ------------------------------------------------------------------ %
    %  Branch C : alpha range sweep                                        %
    % ------------------------------------------------------------------ %
    else
        % Open polar accumulation once — all sweep points land in one file
        lines{end+1} = 'PACC';
        lines{end+1} = POLAR_FILE;
        lines{end+1} = '';                          % no dump file

        % % Prime the solver with the first angle before the sweep so that
        % % XFOIL has a good starting solution for the ASEQ command.
        % lines{end+1} = sprintf('ALFA %g', a_start);
        % 
        % % ASEQ sweeps alpha_start → alpha_end in steps of alpha_step and
        % % writes every converged point into the open PACC polar file.
        % lines{end+1} = sprintf('ASEQ %g %g %g', a_start, a_end, a_step);
        % 
        % % Close the polar accumulator
        % lines{end+1} = 'PACC';

        % -- Per-angle Cp and Cf files ---------------------------------
        % Re-visit each angle and dump Cp / Cf individually.
        % XFOIL re-uses the converged solution from the sweep (same Re,
        % same geometry), so these extra ALFA calls are nearly free.
        for k = 1:numel(alpha_vec)
            a = alpha_vec(k);

            % File names encode the angle; use 2 decimal places so they
            % sort lexicographically and remain unambiguous for negatives.
            cp_k = fullfile(OUTPUT_DIR, sprintf('cp_a%+07.2f.txt', a));
            bl_k = fullfile(OUTPUT_DIR, sprintf('bl_a%+07.2f.txt', a));

            lines{end+1} = sprintf('ALFA %g', a);

            lines{end+1} = 'CPWR';
            lines{end+1} = cp_k;

            lines{end+1} = 'DUMP';
            lines{end+1} = bl_k;
        end
    end

    % -- Exit OPER, quit XFOIL -----------------------------------------
    lines{end+1} = '';
    lines{end+1} = 'QUIT';

    % ------------------------------------------------------------------ %
    %  4. Write the script file                                            %
    % ------------------------------------------------------------------ %
    fid = fopen(SCRIPT_FILE, 'w');
    if fid == -1
        error('generate_xfoil_input: cannot create file ''%s''.', SCRIPT_FILE);
    end
    for k = 1:numel(lines)
        fprintf(fid, '%s\n', lines{k});
    end
    fclose(fid);

    % ------------------------------------------------------------------ %
    %  5. Report to the user                                               %
    % ------------------------------------------------------------------ %
    fprintf('\nXFOIL input script generated\n');
    fprintf('  Script file : %s\n', SCRIPT_FILE);
    fprintf('  Geometry    : %s\n', geom_file);
    fprintf('  Panels      : %d\n', N_PANELS);
    fprintf('  Reynolds    : %.4g\n', Re);

    if ~isempty(alpha_val)
        fprintf('  Mode        : single alpha\n');
        fprintf('  AoA (alpha) : %.4g deg\n', alpha_val);
        fprintf('  Cp output   : cp_<alpha>.txt\n');
        fprintf('  BL output   : bl_<alpha>.txt\n');
    elseif ~isempty(cl_val)
        fprintf('  Mode        : single CL\n');
        fprintf('  Target CL   : %.4g\n', cl_val);
        fprintf('  Cp output   : cp_<cl>.txt\n');
        fprintf('  BL output   : bl_<cl>.txt\n');
    else
        fprintf('  Mode        : alpha range sweep\n');
        fprintf('  Alpha range : %.4g to %.4g deg, step %.4g deg (%d points)\n', ...
                a_start, a_end, a_step, numel(alpha_vec));
        fprintf('  Cp outputs  : cp_<alpha>.txt  (one per angle)\n');
        fprintf('  BL outputs  : bl_<alpha>.txt  (one per angle)\n');
    end

    fprintf('  Polar output: %s\n', POLAR_FILE);
end