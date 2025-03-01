clear all;
clear all;
clc;
import casadi.*

%% 
J = 1; % no frictioinal impulse
J = 1/32; % frictional impulse apperas
above_ground = 0.1;
%% init nosnoc
settings = NosnocOptions();  
model = NosnocModel();
%% settings
settings.irk_scheme = IRKSchemes.RADAU_IIA;
settings.n_s = 1;
settings.dcs_mode = 'Step';
settings.pss_lift_step_functions= 1;
settings.opts_casadi_nlp.ipopt.max_iter = 3e2;
settings.print_level = 2;
settings.N_homotopy = 10;
settings.cross_comp_mode = 1;
settings.psi_fun_type = CFunctionType.STEFFENSON_ULBRICH;
settings.time_freezing = 1;
%%

model.e = 0;
model.mu_f = 1;
model.dims.n_dim_contact = 2;
%% the dynamics

model.a_n = 100;
qx = MX.sym('qx',1);
qy = MX.sym('qy',1);
qtheta = MX.sym('qtheta',1);
vx = MX.sym('vx',1);
vy = MX.sym('vy',1);
omega = MX.sym('omega',1);
q = [qx;qy;qtheta];
v = [vx;vy;omega];
model.x = [q;v];
model.q = q;
model.v = v;
% constraint
m = 1; l = 1;
theta0 = pi/6;
g = 9.81;
M = diag([m,m,J]);
model.M = M;
% contact points of the rod
yc = qy-l/2*cos(qtheta);
xc = qx-l/2*sin(qtheta);
model.f_v = [0;-g;0];
model.f_c = yc;
model.J_tangent = xc.jacobian(q)';
% tangent
model.x0 = [0;l/2*cos(theta0)+above_ground;theta0 ;...
           -10;0;0];
%% Simulation settings
N_finite_elements = 3;
T_sim = 0.6;
N_sim = 40;
model.T_sim = T_sim;
settings.N_finite_elements = N_finite_elements;
model.N_sim = N_sim;
settings.use_previous_solution_as_initial_guess = 1;
%% Call FESD Integrator
[model,settings] = time_freezing_reformulation(model,settings);
settings.time_freezing = 0;
settings.use_speed_of_time_variables = 0;
settings.local_speed_of_time_variable = 0;
[results,stats,solver] = integrator_fesd(model,settings);
%%
qx = results.x(1,:);
qy = results.x(2,:);
qtheta = results.x(3,:);
vx = results.x(4,:);
vy = results.x(5,:);
omega = results.x(6,:);
t = results.x(7,:);
xc_res  = [];
yc_res  = [];
for ii = 1:length(qx)
    xc_res  = [xc_res, qx(ii)-l/2*sin(qtheta(ii))];
    yc_res  = [yc_res,qy(ii)-l/2*cos(qtheta(ii))];
end
%%
h = solver.model.h_k;
figure
for ii = 1:length(qx)
    plot([qx(ii)+l/2*sin(qtheta(ii)) xc_res(ii)],[qy(ii)+l/2*cos(qtheta(ii)) yc_res(ii)],'k','LineWidth',1.5)
    hold on
    yline(0,'r')
    xlabel('$q_x$','Interpreter','latex')
    ylabel('$q_y$','Interpreter','latex')
    axis equal
    ylim([-0.1 2])
    grid on
    pause(h)
    clf
end
%%
figure
plot(t,vx)
hold on
plot(t,vy)
plot(t,omega)
xlabel('$t$','Interpreter','latex')
ylabel('$v$','Interpreter','latex')
grid on
