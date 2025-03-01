% BSD 2-Clause License

% Copyright (c) 2022, Armin Nurkanović, Jonathan Frey, Anton Pozharskiy, Moritz Diehl

% Redistribution and use in source and binary forms, with or without
% modification, are permitted provided that the following conditions are met:

% 1. Redistributions of source code must retain the above copyright notice, this
%    list of conditions and the following disclaimer.

% 2. Redistributions in binary form must reproduce the above copyright notice,
%    this list of conditions and the following disclaimer in the documentation
%    and/or other materials provided with the distribution.

% THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
% AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
% IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
% DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE
% FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
% DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
% SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
% CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
% OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
% OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

% This file is part of NOSNOC.

%

%% Info
% Example 4.1 from 
% Dieci, Luca, and Nicola Guglielmi. "Regularizing piecewise smooth differential systems: co-dimension $ $2 $$ discontinuity surface." Journal of Dynamics and Differential Equations 25.1 (2013): 71-94.

%%
clear all
clc
close all
import casadi.*
%% discretization settings
N_finite_elements = 3;
T_sim = 20;
N_sim  = 100;

%% init
settings = NosnocOptions();
model = NosnocModel();
%% settings
settings.irk_scheme = IRKSchemes.RADAU_IIA; %IRKSchemes.GAUSS_LEGENDRE;
settings.print_level = 2;
settings.n_s = 4;
settings.dcs_mode = 'Stewart'; % 'Step;
settings.mpcc_mode = 'elastic_ell_1_two_sided';  % experimental 
settings.comp_tol = 1e-9;
settings.cross_comp_mode  = 3;
settings.homotopy_update_rule = 'superlinear';
settings.pss_lift_step_functions = 0;
%% Time settings
model.T_sim = T_sim;
model.N_sim = N_sim;
settings.N_finite_elements = N_finite_elements;
%% model
model.x0 = [0.04;-0.01;-0.02];
% Variable defintion
x1 = SX.sym('x1',1);
x2 = SX.sym('x2',1);
x3 = SX.sym('x3',1);
x = [x1;x2;x3];

c = [x2-0.2; x3-0.4];

f_11 = [(x2+x3)/2;-x1+1/(1.2-x2);-x1+1/(1.4-x3)];
f_12 = [(x2+x3)/2;-x1+1/(1.2-x2);-x1+1/(0.6+x3)];
f_13 = [(x2+x3)/2;-x1-1/(0.8+x2);-x1+1/(1.4-x3)];
f_14 = [(x2+x3)/2+x1*(x2+0.8)*(x3+0.6);-x1-1/(0.8+x2);-x1-1/(0.6+x3)];

model.x = x;
model.c = c;
model.S = [-1 -1;-1 1;1 -1; 1 1];

F = [f_11 f_12 f_13 f_14];
model.F = F;
%% Call integrator
[results,stats,solver] = integrator_fesd(model,settings);

%% Plot results
x1 = results.x(1,:);
x2 = results.x(2,:);
x3 = results.x(3,:);

if isequal(settings.dcs_mode,'Stewart')
    theta = results.theta;
else
    alpha = results.alpha;
end
t_grid = results.t_grid;


figure
subplot(131)
plot(t_grid,x1);
xlabel('$t$','Interpreter','latex');
ylabel('$x_1(t)$','Interpreter','latex');
grid on
subplot(132)
plot(t_grid,x2);
xlabel('$t$','Interpreter','latex');
ylabel('$x_2(t)$','Interpreter','latex');
grid on
subplot(133)
plot(t_grid,x3);
xlabel('$t$','Interpreter','latex');
ylabel('$x_3(t)$','Interpreter','latex');
grid on

figure
plot(x1,x3)
xlabel('$x_1$','Interpreter','latex');
ylabel('$x_3$','Interpreter','latex');
grid on

%%
figure
if isequal(settings.dcs_mode,'Stewart')
    plot(t_grid,[[nan;nan;nan;nan],theta])
    xlabel('$t$','Interpreter','latex');
    ylabel('$\theta(t)$','Interpreter','latex');
    grid on    
    legend({'$\theta_1(t)$','$\theta_2(t)$','$\theta_3(t)$','$\theta_4(t)$'},'Interpreter','latex');
else
    plot(t_grid,[[nan;nan],alpha])
    xlabel('$t$','Interpreter','latex');
    ylabel('$\alpha(t)$','Interpreter','latex');
    grid on       
end
