function [exit_code, timed_out] = run_xfoil(varargin)
% RUN_XFOIL  Execute XFOIL using 'xfoil_input.txt' as the batch script.
%
% USAGE
%   [exit_code, timed_out] = run_xfoil()
%   [exit_code, timed_out] = run_xfoil(Name, Value, ...)
%
% OPTIONAL NAME-VALUE PAIRS
%   'xfoil_path'   - Path to the XFOIL executable.
%                    Default: 'xfoil' on Linux/macOS, 'xfoil.exe' on Windows.
%   'script_file'  - Path to the XFOIL batch input script.
%                    Default: 'xfoil_input.txt'
%   'timeout'      - Maximum allowed wall-clock time in seconds before the
%                    process is forcibly killed. Default: 30.
%   'log_file'     - Path to write XFOIL stdout/stderr output.
%                    Default: '' (discard output).
%                    Set to e.g. 'xfoil.log' to retain it for debugging,
%                    or use verbose=true to echo it to the command window.
%   'verbose'      - If true, echoes all XFOIL output live to the MATLAB
%                    command window. Default: false.
%
% OUTPUTS
%   exit_code  - Integer exit code returned by XFOIL (0 = normal exit).
%                Returns -1 if the process could not be started.
%   timed_out  - true  if XFOIL was killed because it exceeded 'timeout'.
%                false otherwise.
%
% NOTES
%   • Graphics suppression (pplot.exe / pxplot.exe) is handled inside the
%     XFOIL input script via the PLOP / G F commands — not here.
%   • This function uses Java's ProcessBuilder (always available in MATLAB)
%     so it works on Windows, Linux, and macOS without any toolbox.
%   • java.lang.ProcessBuilder.Redirect (a static inner class) cannot be
%     resolved through MATLAB's Java bridge, so stdout/stderr are always
%     captured through a pipe and handled in MATLAB instead.
%   • DISPLAY and WAYLAND_DISPLAY are always cleared on Linux/macOS to
%     prevent any residual X11/Wayland GUI attempts.
%
% EXAMPLES
%   % Silent run, 30-second timeout (defaults)
%   [ec, to] = run_xfoil();
%
%   % Echo all XFOIL output to the command window (useful for debugging)
%   [ec, to] = run_xfoil('verbose', true);
%
%   % Save output to a log file
%   [ec, to] = run_xfoil('log_file', 'xfoil.log');

    % ------------------------------------------------------------------ %
    %  1. Parse inputs                                                     %
    % ------------------------------------------------------------------ %
    is_win = ispc();

    p = inputParser();
    addParameter(p, 'xfoil_path',      default_exe(),     @(x) ischar(x) || isstring(x));
    addParameter(p, 'script_file',     'xfoil_input.txt', @(x) ischar(x) || isstring(x));
    addParameter(p, 'timeout',         30,                @(x) isnumeric(x) && isscalar(x) && x > 0);
    addParameter(p, 'log_file',        '',                @(x) ischar(x) || isstring(x));
    addParameter(p, 'verbose',         true,              @(x) islogical(x) || isnumeric(x));
    addParameter(p, 'print_xfoil_out', false,             @(x) islogical(x) || isnumeric(x));
    parse(p, varargin{:});
    r = p.Results;

    xfoil_exe       = char(r.xfoil_path);
    script_file     = char(r.script_file);
    log_file        = char(r.log_file);
    timeout_s       = r.timeout;
    verbose         = logical(r.verbose);
    print_xfoil_out = logical(r.print_xfoil_out);

    exit_code = -1;
    timed_out = false;

    % ------------------------------------------------------------------ %
    %  2. Sanity checks                                                    %
    % ------------------------------------------------------------------ %
    if ~isfile(script_file)
        error('run_xfoil: script file not found: %s', script_file);
    end

    script_file = absolute_path(script_file);
    if ~isempty(log_file)
        log_file = absolute_path(log_file);
    end

    % ------------------------------------------------------------------ %
    %  3. Build the OS command                                             %
    % ------------------------------------------------------------------ %
    if is_win
        cmd_list = {'cmd', '/c', xfoil_exe, '<', script_file};
    else
        cmd_list = {'sh', '-c', sprintf('%s < %s', ...
                    escape_posix(xfoil_exe), escape_posix(script_file))};
    end

    % ------------------------------------------------------------------ %
    %  4. Launch via Java ProcessBuilder                                   %
    % ------------------------------------------------------------------ %
    try
        pb = java.lang.ProcessBuilder(cmd_list);

        % Working directory = folder of the script file
        script_dir = fileparts(script_file);
        if ~isempty(script_dir)
            pb.directory(java.io.File(script_dir));
        end

        % Always strip display variables on POSIX — graphics suppression
        % is the XFOIL script's responsibility (PLOP / G F), but clearing
        % these is a harmless safety net against any X11/Wayland attempt.
        if ~is_win
            env = pb.environment();
            env.remove('DISPLAY');
            env.remove('WAYLAND_DISPLAY');
        end

        % Merge stderr into stdout so we only need one reader.
        % (java.lang.ProcessBuilder.Redirect is a static inner class that
        % MATLAB's Java bridge cannot resolve, so we never call
        % pb.inheritIO() or pb.redirectOutput(Redirect.DISCARD).)
        pb.redirectErrorStream(true);

        if verbose
            fprintf('\nrun_xfoil: starting XFOIL  [timeout: %g s]\n', timeout_s);
        end

        t_start = tic();
        process = pb.start();

    catch ME
        error('run_xfoil: failed to launch XFOIL process.\n  %s', ME.message);
    end

    % Open stdout reader (single pipe because redirectErrorStream=true)
    stdout_reader = java.io.BufferedReader( ...
                        java.io.InputStreamReader( ...
                            process.getInputStream()));

    % Open log file if requested
    log_fid = -1;
    if ~isempty(log_file)
        log_fid = fopen(log_file, 'w');
        if log_fid == -1
            warning('run_xfoil: could not open log file for writing: %s', log_file);
        elseif verbose
            fprintf('run_xfoil: XFOIL output → %s\n', log_file);
        end
    end

    % ------------------------------------------------------------------ %
    %  5. Wait for completion, enforcing the timeout                       %
    %     Drain stdout continuously to prevent pipe-buffer deadlock.       %
    % ------------------------------------------------------------------ %
    POLL_INTERVAL = 0.05;   % seconds between liveness checks

    finished = false;
    while true
        elapsed = toc(t_start);

        drain_pipe(stdout_reader, print_xfoil_out, log_fid);

        try
            exit_code = process.exitValue();   % throws if still running
            finished  = true;
            drain_pipe(stdout_reader, print_xfoil_out, log_fid);   % final flush
            break;
        catch
            % Still running
        end

        if elapsed >= timeout_s
            timed_out = true;
            
            if is_win
                
                % 3. NUCLEAR OPTION: If the window is still there, 
                % kill all xfoil.exe instances to be safe.
                system('taskkill /F /IM xfoil.exe /T');
            else
                process.destroyForcibly();
            end

            if verbose
                fprintf('run_xfoil: TIMEOUT (%.1f s) — Forcing XFOIL closure.\n', elapsed);
            end
            break;
        end

        pause(POLL_INTERVAL);
    end

    % Close resources
    stdout_reader.close();
    if log_fid ~= -1
        fclose(log_fid);
    end

    % ------------------------------------------------------------------ %
    %  6. Report                                                           %
    % ------------------------------------------------------------------ %
    if verbose
        elapsed = toc(t_start);
        if finished
            fprintf('run_xfoil: finished in %.2f s  (exit code: %d)\n', ...
                    elapsed, exit_code);
        end
        if timed_out
            fprintf('run_xfoil: results may be incomplete (unconverged).\n');
        end
        if log_fid ~= -1 && isfile(log_file)
            fprintf('run_xfoil: XFOIL log saved to %s\n', log_file);
        end
    end
end


% ========================================================================
%  HELPERS
% ========================================================================

function drain_pipe(reader, print_xfoil_out, log_fid)
% Drain all currently-available lines from the pipe.
%   verbose=true   → echo to the MATLAB command window.
%   log_fid ~= -1  → write to the log file.
%   otherwise      → read and discard to prevent pipe-buffer deadlock.
    while reader.ready()
        line = char(reader.readLine());
        if print_xfoil_out
            fprintf('%s\n', line);
        end
        if log_fid ~= -1
            fprintf(log_fid, '%s\n', line);
        end
    end
end

function exe = default_exe()
    if ispc()
        exe = 'xfoil.exe';
    else
        exe = 'xfoil';
    end
end

function s = escape_posix(s)
    s = char(s);
    s = strrep(s, "'", "'\\''");
    s = ['''' s ''''];
end

function p = absolute_path(p)
    try
        p = char(java.io.File(p).getCanonicalPath());
    catch
        % Fall back silently
    end
end