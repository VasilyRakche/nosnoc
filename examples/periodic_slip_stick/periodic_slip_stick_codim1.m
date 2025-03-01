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
% Example 6.1 from 
% Dieci, Luca, and Luciano Lopez. 
% "Sliding motion in Filippov differential systems: theoretical results and a computational approach." 
% SIAM Journal on Numerical Analysis 47.3 (2009): 2023-2051.

%%
clear all
clc
close all
import casadi.*
%% discretization settings
N_finite_elements = 2;
T_sim = 40;
N_sim  = 100;
%% init
settings = NosnocOptions();
model = NosnocModel();
%% settings
settings.use_fesd = 1;
settings.irk_scheme = IRKSchemes.RADAU_IIA; %IRKSchemes.GAUSS_LEGENDRE;
settings.print_level = 2;
settings.n_s = 2;
settings.dcs_mode = 'Stewart'; % 'Step;
settings.comp_tol = 1e-9;
settings.cross_comp_mode  = 3;
settings.homotopy_update_rule = 'superlinear';
%% Time settings
settings.N_finite_elements = N_finite_elements;
model.T_sim = T_sim;
model.N_sim = N_sim;
% Inital Value
model.x0 = [0.04;-0.01];
model.x0 = [-0.8;-1];
% Variable defintion
x1 = SX.sym('x1',1);
x2 = SX.sym('x2',1);
x = [x1;x2];

c = x2-0.2;

f_11 = [x2;-x1+1/(1.2-x2)];
f_12 = [x2;-x1-1/(0.8+x2)];


model.x = x;
model.c = c;
model.S = [-1;1];

F = [f_11 f_12];
model.F = F;
%% Call integrator
[results,stats,solver] = integrator_fesd(model,settings);

%% Plot results
x1 = results.x(1,:);
x2 = results.x(2,:);

if isequal(settings.dcs_mode,'Stewart')
    theta = results.theta;
else
    alpha = results.alpha;
end
t_grid = results.t_grid;

figure
subplot(121)
plot(t_grid,x1);
xlabel('$t$','Interpreter','latex');
ylabel('$x_1(t)$','Interpreter','latex');
grid on
subplot(122)
plot(t_grid,x2);
xlabel('$t$','Interpreter','latex');
ylabel('$x_2(t)$','Interpreter','latex');
grid on

figure
plot(x1,x2)
xlabel('$x_1$','Interpreter','latex');
ylabel('$x_2$','Interpreter','latex');
grid on

%%
figure
if isequal(settings.dcs_mode,'Stewart')
    plot(t_grid,[[nan;nan],theta])
    xlabel('$t$','Interpreter','latex');
    ylabel('$\theta(t)$','Interpreter','latex');
    grid on    
    legend({'$\theta_1(t)$','$\theta_2(t)$'},'Interpreter','latex');
else
    plot(t_grid,[nan,alpha])
    xlabel('$t$','Interpreter','latex');
    ylabel('$\alpha(t)$','Interpreter','latex');
    grid on       
end
