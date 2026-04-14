function [x, y] = CSTcurve(x, A)
    % CST_eval - Evaluate Class-Shape Transformation curve
    % x  : vector of x positions (0 <= x <= 1)
    % A  : vector of shape coefficients [A0, A1, ..., An]
    % N1 : exponent for leading edge (typically 0.5)
    % N2 : exponent for trailing edge (typically 1.0)

    N1 = 0.5;
    N2 = 1.0;

    n = length(A) - 1;          % order of Bernstein polynomial
    C = x.^N1 .* (1 - x).^N2;   % Class function

    % Compute shape function S(x)
    S = zeros(size(x));
    for i = 0:n
        bin_coeff = nchoosek(n, i);
        S = S + A(i+1) * bin_coeff .* x.^i .* (1 - x).^(n - i);
    end

    % Final CST shape
    y = C .* S;
end
