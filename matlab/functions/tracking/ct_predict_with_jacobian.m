function [xPred, F] = ct_predict_with_jacobian(x, dt)
    % CT_PREDICT_WITH_JACOBIAN  Constant-turn prediction and Jacobian F.
    %
    % State x = [px; py; v; psi; omega]. Straight-line model for |omega| ~ 0.

    px = x(1);
    py = x(2);
    v = x(3);
    psi = x(4);
    omega = x(5);

    epsOmega = 1e-4;

    if abs(omega) < epsOmega

        px2 = px + v * cos(psi) * dt;
        py2 = py + v * sin(psi) * dt;
        v2 = v;
        psi2 = psi + omega * dt;
        omega2 = omega;

        F = eye(5);

        F(1,3) = cos(psi) * dt;
        F(1,4) = -v * sin(psi) * dt;

        F(2,3) = sin(psi) * dt;
        F(2,4) = v * cos(psi) * dt;

        F(4,5) = dt;

    else

        psiNext = psi + omega * dt;

        px2 = px + (v / omega) * (sin(psiNext) - sin(psi));
        py2 = py + (v / omega) * (-cos(psiNext) + cos(psi));
        v2 = v;
        psi2 = psiNext;
        omega2 = omega;

        F = eye(5);

        F(1,3) = (sin(psiNext) - sin(psi)) / omega;
        F(1,4) = (v / omega) * (cos(psiNext) - cos(psi));
        F(1,5) = ...
            -v / omega^2 * (sin(psiNext) - sin(psi)) + ...
             v / omega * cos(psiNext) * dt;

        F(2,3) = (-cos(psiNext) + cos(psi)) / omega;
        F(2,4) = (v / omega) * (sin(psiNext) - sin(psi));
        F(2,5) = ...
            -v / omega^2 * (-cos(psiNext) + cos(psi)) + ...
             v / omega * sin(psiNext) * dt;

        F(4,5) = dt;
    end

    xPred = [px2; py2; v2; wrapToPi_local(psi2); omega2];
end
