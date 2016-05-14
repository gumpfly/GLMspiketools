function [gg,neglogli,H,neglogp] = MAPfit_GLMbi_coordascent(gg,Stim,Cx,Ct,maxiter,ftol,optimArgs)
%  [gg,neglogli,H,neglogp] = MAPfit_GLMbi_coordascent(gg,Stim,maxiter,ftol,optimArgs);
% 
%  Computes the MAP estimate for GLM params, with gradient and hessians, via
%  coordinate ascent, for bilinear (low rank) parametrization of space-time filter.
%
%  Inputs: 
%     gg = param struct
%     Stim = stimulus
%       Cx = inverse covariance for spatial params
%       Ct = inverse covariance for temporal params
%     maxiter = maximum number of coordinate ascent steps 
%     ftol = tolerance for stopping based on function improvement 
%     optimArgs = cell array of optimization params (optional)
%
%  Outputs:
%     ggnew = new param struct (with ML params);
%     fval = negative log-likelihood at ML estimate
%        H = Hessian of negative log-likelihood at ML estimate

% Set maxiter if necessary
if (nargin <= 3) || isempty(maxiter)
    maxiter = 50;  % maximum number of coordinate ascent steps
end
if (nargin <=4) || isempty(ftol)
    ftol = .001;  % tolerance for stopping
end

% Set optimization parameters 
if nargin < 6
    optimArgs = [];
end

% create struct for spatial optimization
ggx = gg;
ggx.ktype = 'linear'; % set type to linear (from bilinear)
ggx.ktbas = 1; ggx.ktbasprs = []; % remove temporal basis
ggx.kt = gg.kx(:)';
ggx.k = ggx.kt;

% create struct for temporal optimization
ggt = gg;
ggt.ktype = 'linear'; % set type to linear (from bilinear)
ggt.kt = gg.kt;
ggt.k = ggt.ktbas*ggt.kt;

% Initialize spatial stimulus 
[nt,nkx] = size(Stim);
krank = gg.krank;
xStim = zeros(nt,krank*nkx); % initialize spatial stimulus

% compute initial log-likelihood
neglogli0 = neglogli_GLM(gg,Stim); % Compute logli of initial params
dlogp = inf;  % initialize change in log-posterior
jjiter = 0;  % initialize counter

% compute initial penalties (negative log prior)
nlpx = .5*gg.kx(:)'*Cx*gg.kx(:)
nlpt = .5*gg.kt(:)'*Ct*gg.kt(:)
neglogp0 = neglogli0+nlpx+nlpt;

while (jjiter<maxiter) && dlogp>ftol
    
    % ---- Update temporal params -----
    fprintf('Iter #%d: Updating temporal params\n', jjiter);
    tStim = Stim*reshape(ggx.k',[],gg.krank);
    ggt.dc = ggx.dc;  % update dc param
    [ggt,tneglogli] = MAPfit_GLM(ggt,tStim,Ct,optimArgs);
    nlpt = .5*ggt.kt(:)'*Ct*ggt.kt(:);
    fprintf('dlogp = %.4f\n\n', neglogp0-(tneglogli+nlpt+nlpx));
    
    % Convolve stimulus with temporal filters
    for irank = 1:krank
        for icol = 1:nkx
            xStim(:,icol+(irank-1)*nkx) = sameconv(Stim(:,icol),ggt.k(:,irank));
        end
    end
    
    % ---- Update spatial params ----
    fprintf('Iter #%d: Updating spatial params\n', jjiter);
    ggx.dc = ggt.dc; % update dc param
    [ggx,xneglogli] = MAPfit_GLM(ggx,xStim,Cx,optimArgs);
    nlpx = .5*ggx.k(:)'*Cx*ggx.k(:);
    neglogp = xneglogli+nlpt+nlpx;
    fprintf('dlogp = %.4f\n\n', neglogp0-neglogp);

    % Update iters
    jjiter = jjiter+1;  % counter
    dlogp = neglogp0-neglogp; % change in log-likelihood
    neglogp0 = neglogp;
    
end

fprintf('\nFinished coordinate ascent: %d iterations (dlogp=%.6f)\n',jjiter,dlogp);

% Compute conditional Hessians, if desired
if nargout > 2

    % Compute Hessian for time components
    tStim = Stim*(ggx.k');
    ggt.dc = ggx.dc;  % update dc param
    [ggt,~,Ht] = MAPfit_GLM(ggt,tStim,Ct,optimArgs);
    nlpt = .5*ggt.kt(:)'*Ct*ggt.kt(:);

    % Compute Hessian for space components
    for irank = 1:krank
        for icol = 1:nkx
            xStim(:,icol+(irank-1)*nkx) = sameconv(Stim(:,icol),ggt.k(:,irank));
        end
    end    
    ggx.dc = ggt.dc; % update dc param
    [ggx,xneglogli,Hx] = MAPfit_GLM(ggx,xStim,Cx,optimArgs);
    nlpx = .5*ggx.k(:)'*Cx*ggx.k(:);
    neglogp = xneglogli+nlpt+nlpx;
    H = {Ht,Hx};  % Hessians for t and x components
end

% Update params of bilinear model
gg.dc = ggx.dc;
gg.kt = ggt.kt;
gg.kx = reshape(ggx.k',[],gg.krank);
gg.k = (gg.ktbas*gg.kt)*gg.kx';
neglogli = xneglogli;
