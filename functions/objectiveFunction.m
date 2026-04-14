function err = objectiveFunction(A, xObj, yObj, xInterp)

    % taking a vector of CST coefficients, this shit evaluates the distance
    % in RMS terms from the objective curve
    % A = [A1 A2 A3 A4 A5 A6 ...]
        
    if length(xObj) ~= length(xInterp)
        error("Number of points not equal to objective curve.")
    end

    [x, y] = CSTcurve(xInterp, A);
    N = length(xInterp);
    errY = sqrt(1/N * sum((y - yObj).^2));
    errX = 0;
    err = norm([errX, errY]);
    
    % plotting to see the points get closer
    doPlot = 0;
    if doPlot
        hold off
        plot(xObj, yObj, "r")
        axis([0 1 -.15 .15])
        hold on
        plot(x, y, "b");
        pause(0.01)
    end

end