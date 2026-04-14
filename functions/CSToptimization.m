function [T, B, success] = CSToptimization(xP, yP)

    % find the element that separates the upper and lower surfaces.
    % Depending on coordinate definition you have to set nIndex either
    % equal to 0 or 1. LE = Leading Edge.
    nIndex = 0;
    LEIndex = find(xP == nIndex);
    if length(LEIndex) > 1 && LEIndex(2) == LEIndex(1) + 1
        nIndex = 1;
    end
    % get back only the first point.
    LEIndex = LEIndex(1);
    
    % separate the upper and lower surfaces
    xPu = xP(1:LEIndex);
    yPu = yP(1:LEIndex);
    xPl = xP(LEIndex + nIndex:end);
    yPl = yP(LEIndex + nIndex:end);
    
    % make sure that upper and lower points are in ascending x order
    if any(xPu ~= sort(xPu))
        [xPu, idx] = sort(xPu, 'ascend');
        yPu = yPu(idx);
    end
    
    if any(xPl ~= sort(xPl))
        [xPl, idx] = sort(xPl, 'ascend');
        yPl = yPl(idx);
    end
    
    % delete any duplicate elements of lower and upper surface.
    [xPl, idx] = unique(xPl, "stable");
    yPl = yPl(idx);
    
    [xPu, idx] = unique(xPu, "stable");
    yPu = yPu(idx);
    
    % interpolating the values pizello
    % ALSO: the x-values for the interpolation are always from 0 to 1;
    % So you'll have to stitch them up nicely if you want to have the classic
    % sweeping airfoil coordinates (TE -> LE -> TE  ;  x=1 -> x=0 -> x=1)
    F = griddedInterpolant(xPu, yPu, "makima");
    G = griddedInterpolant(xPl, yPl, "makima");
    % now you call F(xq) to interpolate on xq.
    
    % CST polynomial coefficients
    T0 =  0.5 * ones(8, 1);
    B0 = -0.5 * ones(8, 1);
    
    % we interpolate the airfoil points given, to make it smoother.
    % we then want to optimize the coefficients such that the distance
    % between the red curve and the blue dots is minimized.
    xInterpU = (1-cos(linspace(0, pi, 200)))/2;
    yInterpU = F(xInterpU);
    
    xInterpL = (1-cos(linspace(0, pi, 200)))/2;
    yInterpL = G(xInterpL);
    
    xCSTu = xInterpU;
    xCSTl = xInterpL;

    options = optimoptions("fminunc", "Display", "none");

    try    
        % UPPER SURFACE MINIMIZATION
        T = fminunc(@(x) objectiveFunction(x, xInterpU, yInterpU, xCSTu), T0, options);
        
        % LOWER SURFACE CONVERGENCE
        B = fminunc(@(x) objectiveFunction(x, xInterpL, yInterpL, xCSTl), B0, options);

        success = true;
    catch
        success = false;
    end
end



function err = objectiveFunction(A, xObj, yObj, xInterp)

    % taking a vector of CST coefficients, this shit evaluates the distance
    % in RMS terms from the objective curve
    % A = [A1 A2 A3 A4 A5 A6 ...]
        
    if length(xObj) ~= length(xInterp)
        error("Number of points not equal to objective curve.")
    end

    [~, y] = CSTcurve(xInterp, A);
    N = length(xInterp);
    errY = sqrt(1/N * sum((y - yObj).^2));
    errX = 0;
    err = norm([errX, errY]);

end