%    This file is part of NOSNOC.
%
%    NOSNOC -- A software for NOnSmooth Numerical Optimal Control.
%    Copyright (C) 2022 Armin Nurkanovic, Moritz Diehl (ALU Freiburg).
%
%    NOSNOC is free software; you can redistribute it and/or
%    modify it under the terms of the GNU Lesser General Public
%    License as published by the Free Software Foundation; either
%    version 3 of the License, or (at your option) any later version.
%
%    NOSNOC is distributed in the hope that it will be useful,
%    but WITHOUT ANY WARRANTY; without even the implied warranty of
%    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
%    Lesser General Public License for more details.
%
%    You should have received a copy of the GNU Lesser General Public
%    License along with NOSNOC; if not, write to the Free Software Foundation,
%    Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301  USA
%
%
function [varargout] = create_nlp_nosnoc_opti(varargin)
% Info on this function.
%% read data
model = varargin{1};
settings = varargin{2};
%% CasADi
import casadi.*
%% Reformulation of the PSS into a DCS
[settings] = refine_user_settings(settings);
[model,settings] = model_reformulation_nosnoc(model,settings);

%% Fillin missing settings with default settings
[settings] = fill_in_missing_settings(settings,model);

%% Load user settings and model details
unfold_struct(settings,'caller')
unfold_struct(model,'caller');
%% Bounds on step-size (if FESD active)
if use_fesd
    ubh = (1+gamma_h)*h_k;
    lbh = (1-gamma_h)*h_k;
    if time_rescaling && ~use_speed_of_time_variables
        % if only time_rescaling is true, speed of time and step size all lumped together, e.g., \hat{h}_{k,i} = s_n * h_{k,i}, hence the bounds need to be extended.
        ubh = (1+gamma_h)*h_k*s_sot_max;
        lbh = (1-gamma_h)*h_k/s_sot_min;
    end
    % initigal guess for the step-size
    h0_k = h_k.*ones(N_stages,1);
end

%% Butcher Tableu (differential and integral representation)
switch irk_representation
    case 'integral'
        [B,C,D,tau_root] = generatre_butcher_tableu_integral(n_s,irk_scheme);
        if tau_root(end) == 1
            right_boundary_point_explicit  = 1;
        else
            right_boundary_point_explicit  = 0;
        end
    case 'differential'
        [A_irk,b_irk,c_irk,order_irk] = generatre_butcher_tableu(n_s,irk_scheme);
        if c_irk(end) <= 1+1e-9 && c_irk(end) >= 1-1e-9
            right_boundary_point_explicit  = 1;
        else
            right_boundary_point_explicit  = 0;
        end
    otherwise
        error('Choose irk_representation either: ''integral'' or ''differential''')
end

%% Elastic Mode variables
% This will be defind inside the loops and functions for the treatment

%% Time optimal control (time transformations)
if time_optimal_problem
    % the final time in time optimal control problems
    T_final = define_casadi_symbolic(casadi_symbolic_mode,'T_final',1);
    T_final_guess = T;
end

%% Formulation of the NLP
opti = Opti();

%% Objective terms
J = 0;
J_comp = 0;
J_comp_std = 0;
J_comp_cross = 0;
J_comp_step_eq = 0;
J_regularize_h = 0;
J_regularize_sot = 0;

%% Inital value
X_ki = opti.variable(n_x);
if there_exist_free_x0
    x0_ub = x0;
    x0_lb = x0;
    x0_ub(ind_free_x0) = inf;
    x0_lb(ind_free_x0) = -inf;
    x0(ind_free_x0) = 0;
    opti.subject_to(x0_lb<= X_ki <=x0_ub);
else
    opti.subject_to(X_ki==x0);

end
opti.set_initial(X_ki, x0);

%% Index sets and collcet all variables into vectors
% (TODO: are these index sets needed at all in opti?)
ind_x = [1:n_x];
ind_u = [];
ind_v = [];
ind_z = [];
ind_h = [];
ind_elastic = [];
ind_g_clock_state = [];
ind_vf  = [];
ind_sot = []; % index for speed of time variable
ind_boundary = []; % index of bundary value lambda and mu
ind_total = ind_x;
% Collect all states/controls
%% TODO: Consider dropping the s in Xs, Us etc.
X_boundary = {X_ki}; % differentail on FE boundary
X = {X_ki}; % differential on all points
Z = {};  % algebraic - PSS
Z_DAE = {}; % algebraic - DAE
U = {}; % Controls
H = {}; % Step-sizes
S_sot = {}; % Speed-of time
S_elastic = {}; % Elastic

%% Other initalizations of sums
sum_h_ki = []; % a vector of N_ctrl x 1, collecting all sums
sum_h_ki_all = 0; %  %TODO: make this at the end as sum of the entries of sum_h_ki; Note that this is the integral of the clock state if no time-freezing is used.
clock_state_integral_smooth = 0; % clock_state_integral_smooth
% Initalization of forward and backward sums for the step-equilibration
sigma_theta_B_k = 0; % backward sum of theta at finite element k
sigma_theta_F_k = 0; % forward sum of theta at finite element k
sigma_lambda_B_k = 0; % backward sum of lambda at finite element k
sigma_lambda_F_k = 0; % forward sum of lambda at finite element k
nu_vector = [];

% Continuity of lambda initalization
lambda_end_previous_fe = zeros(n_theta,1);
% What is this Z_kd_end??
Z_kd_end = zeros(n_z,1);
% % initialize cross comp and mpcc related structs
% mpcc_var_current_fe.p = p;
% comp_var_current_fe.cross_comp_control_interval_k = 0;
% comp_var_current_fe.cross_comp_control_interval_all = 0;
n_cross_comp = zeros(max(N_finite_elements),N_stages);
%% Index nomenclature
%  k - control interval  {0,...,N_ctrl-1}
%  i - finite element    {0,...,N_fe-1}
%  j - stage             {1,...,n_s}
% TODO rename all Xk to X_k, all Uk to U_k, etc. to be consistent and increase readibility.
%% Main NLP loop over control intevrals/stages
for k=0:N_ctrl-1
    %% Define discrete-time control varibles for control interval k
    if n_u >0
        U_k = opti.variable(n_u);
        U{end+1} = U_k;
        opti.subject_to(lbu <= U_k <=ubu);
        opti.set_initial(U_k, u0);
        ind_u = [ind_u,ind_total(end)+1:ind_total(end)+n_u];
        ind_total = [ind_total,ind_total(end)+1:ind_total(end)+n_u];
        if virtual_forces
            % Possibly implement the costs and constraints for virutal forces in time-freezing
        end
    end

    %% Time-transformation variables (either one for the whole horizon or one per control interval)
    if time_rescaling && use_speed_of_time_variables
        if k == 0 || local_speed_of_time_variable
            S_sot_k = opti.variable(n_u);
            S_sot{end+1} = {S_sot_k}; % Speed-of time
            opti.subject_to(s_sot_min <= S_sot_k <=s_sot_max);
            opti.set_initial(S_sot_k, s_sot0); %TODO: rename s_sot0 to S_sot0 in the approipate places
            % index colector for sot variables
            ind_sot = [ind_sot,ind_total(end)+1:ind_total(end)+1];
            ind_total  = [ind_total,ind_total(end)+1:ind_total(end)+1];
            J_regularize_sot = J_regularize_sot+(S_sot_k-S_sot_nominal)^2;
        end
    end

    %% General nonlinear constriant evaluated at left boundary of the control interval
    if g_ineq_constraint
        g_ineq_k = g_ineq_fun(X_ki,U_k);
        opti.subject_to(g_ineq_lb <= g_ineq_k <=g_ineq_ub);
    end

    %% Loop over finite elements for the current control interval
    sum_h_ki_temp = 0; % initalize sum for current control interval
    %% TODO: answer the questions: does vectorizing this loop make sense as vectorizing the loop over the stages below?
    for i = 0:N_FE(k+1)-1
        %%  Sum of all theta and lambda for current finite elememnt
        % Note that these are vector valued functions, sum_lambda_ki
        % contains the right boundary point of the previous interval because of the continuity of lambda (this is essential for switch detection, cf. FESD paper)
        sum_theta_ki = zeros(n_theta,1);
        sum_lambda_ki = lambda_end_previous_fe;
        %% Step-size variables - h_ki;
        if use_fesd
            % Define step-size variables, if FESD is used.
            if  k>0 || i>0
                h_ki_previous = h_ki;
            end
            h_ki = opti.variable(1);
            H{end+1} = h_ki ;
            opti.subject_to(lbh(k+1) <= h_ki <=ubh(k+1));
            opti.set_initial(h_ki, h0_k);
            % index sets for step-size variables
            ind_h = [ind_h,ind_total(end)+1:ind_total(end)+1];
            ind_total  = [ind_total,ind_total(end)+1:ind_total(end)+1];
            sum_h_ki_temp = sum_h_ki_temp + h_ki;

            % delta_h_ki = h_ki -h_{k-1,i}. Obeserve that the delta_h are  computed for every control interval separatly
             if i > 0 
                delta_h_ki = h_ki - h_ki_previous;
            else
                delta_h_ki  = 0;
            end
            % Terms for heuristic step equilibration
            if heuristic_step_equilibration
                switch heuristic_step_equilibration_mode
                    case 1
                        J_regularize_h  = J_regularize_h + (h_ki-h_k(k+1))^2;
                    case 2
                        J_regularize_h  = J_regularize_h + delta_h_ki^2;
                    otherwise
                        % TODO: in refine_settings heuristic_step_equlibration_mode >2, set it to heuristic_step_equlibration_mode = 1
                        error('Pick heuristic_step_equlibration_mode between 1 and 2.');
                end
            end
            % Integral of clock state (if time flows without stopping, i.e., time_freezing = 0)
            if time_optimal_problem && use_speed_of_time_variables
                % TODO: consider writhing this forumla vectorized after all loops
                clock_state_integral_smooth = clock_state_integral_smooth + h_ki*s_sot_k; % integral of clock state (if no time-freezing is used, in time-freezing we use directly the (nonsmooth) differential clock state.
            end
        end
        %% Variables at stage points
        % Defintion of differential variables
        X_ki_stages = opti.variable(n_x, n_s);
        X{end+1} = X_ki_stages;
        opti.subject_to(lbx <= X_ki_stages <=ubx);
        opti.set_initial(X_ki_stages, repmat(x0,1,n_s));
        % Index sets
        ind_x = [ind_x,ind_total(end)+1:ind_total(end)+n_x*n_s];
        ind_total = [ind_total,ind_total(end)+1:ind_total(end)+n_x*n_s];
        % Defintion of algebraic variables
        Zc = opti.variable(n_z, n_s);
        Z{end+1} = Zc;
        opti.subject_to(lbz <= Zc <=ubz);
        opti.set_initial(Zc, repmat(z0,1,n_s));
        % Index sets
        ind_z = [ind_z,ind_total(end)+1:ind_total(end)+n_z*n_s];
        ind_total = [ind_total,ind_total(end)+1:ind_total(end)+n_z*n_s];

        % Evaluate ODE right-hand-side at all stage points
        [f_x, f_q] = f_x_fun(X_ki_stages, Zc, U_k);
        [g_z] = g_z_fun(X_ki_stages, Zc, U_k);

        % Add contribution to quadrature function
        J = J + f_q*B*h;
        % Get interpolating points of collocation polynomial
        X_all = [X_ki X_ki_stages];
        % Get slope of interpolating polynomial (normalized)
        Pidot = X_all*C;
        % Match with ODE right-hand-side
        opti.subject_to(Pidot == h*f_x);
        opti.subject_to(0 == g_z);

        % State at end of finite elemnt
        Xk_end = X_all*D;
        %% New decision variable for state at end of a finite element
        X_ki = opti.variable(n_x);
        X_boundary{end+1} = X_ki;
        X{end+1} = X_ki;
        opti.subject_to(lbx <= X_ki <= ubx);
        opti.set_initial(X_ki, x0);
        ind_x= [ind_x,ind_total(end)+1:ind_total(end)+n_x];
        ind_total = [ind_total,ind_total(end)+1:ind_total(end)+n_x];
        % Continuity constraints
        opti.subject_to(Xk_end==X_ki)
    end
    sum_h_ki = [sum_h_ki;sum_h_ki_temp];
end
sum_h_ki_all = sum(sum_h_ki); % this is the sum of all over all FE and control intervals (= integral of clock state if no time-freezing is used)
%% Terminal Constraints
%  possible relaxation of terminal constraints

% terminal constraint for physical and numerical  time


%% Terminal Costs
% basic terminal cost term

% Quadrature states

% Time-optimal problems

%% Elastic mode cost terms

%% Regularization cost terms
% Regularization term for speed-of-time
% idea: add sot to model reformulation and add f_q (or do it all here, to
% Cost term for grid regularization (step equilibration, heursitic step)

%% Collect all variables
X = [X{:}];
X_boundary = [X_boundary{:}];
U = [U{:}];
Z = [Z{:}];
H = [H{:}];
S_sot = [S_sot{:}];
S_elastic = [S_elastic{:}];
%% CasADi functions for complementarity residuals (standard, cross_complementarity, joint)

%% Create NLP Solver instance
opti.minimize(J);
opti.solver('ipopt'); % TODO: IPOPT Settings; 
%TODO: Loop of problems for incerasing number of iterations, 
% e.g. min iter = 100, max_iter, 1500, make ~equidistant grid of integers on ceil(linspace(min_iter,max_iter,N_homotopy); save all solvers in cell
% sol = opti.solve();
%% Results
% x_opt = sol.value(X_boundary);
% x_opt_extended = sol.value(X);
% z_opt = sol.value(Z);
% u_opt = sol.value(U);
% J_opt = sol.value(J);

%% Model: CasADi functions, dimenesions, auxilairy functions.

%% Solve initalization (bounds, inital guess, parameters)

%% Output of the function
varargout{1} = solver;
varargout{2} = solver_initalization;
varargout{3} = model;
varargout{4} = settings;
end