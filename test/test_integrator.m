function [results,stats,model,settings] = test_integrator(use_fesd, irk_representation, irk_scheme, dcs_mode)
import casadi.*
% discretization settings
N_finite_elements = 2;
T_sim = pi/2;
N_sim  = 29;
R_osc  = 1;


fprintf('use_fesd\tirk_representation\tirk_scheme\tdcs_mode\n')
fprintf('%d\t\t\t%s\t\t\t%s\t\t\t%s\n',use_fesd, irk_representation, irk_scheme, dcs_mode);
settings = NosnocOptions();
settings.use_fesd = use_fesd;
settings.irk_representation = irk_representation;
settings.irk_scheme = irk_scheme;
settings.real_time_plot = 0;
settings.print_level = 2;
settings.n_s = 4;
settings.dcs_mode = dcs_mode;
% 'Stewart'; % 'Step;
settings.comp_tol = 1e-9;
settings.cross_comp_mode  = 3;
settings.homotopy_update_rule = 'superlinear';
settings.N_homotopy = 7;
% Model
x_star = [exp(1);0];
x_star = [exp(T_sim-1)*cos(2*pi*(T_sim-1));-exp((T_sim-1))*sin(2*pi*(T_sim-1))];

model = NosnocModel();
settings.N_finite_elements = N_finite_elements;
model.T_sim = T_sim;
model.N_sim = N_sim;
omega = -2*pi;
A1 = [1 omega;...
    -omega 1];
A2 = [1 -omega;...
    omega 1];
% Inital Value
model.x0 = [exp(-1);0];
% Variable defintion
x1 = SX.sym('x1');
x2 = SX.sym('x2');
x = [x1;x2];
c = x1^2+x2^2-1;
model.x = x;
model.c = c;
model.S = [-1;1];
f_11 = A1*x;
f_12 = A2*x;
F = [f_11 f_12];
model.F = F;
% Call integrator
[results,stats,solver] = integrator_fesd(model,settings);
% numerical error
x_fesd = results.x(:,end);
error_x = norm(x_fesd-x_star,"inf");
fprintf(['Numerical error with h = %2.3f and ' char(settings.irk_scheme) ' with n_s = %d stages is: %5.2e: \n'],model.h_sim,settings.n_s,error_x);
end
