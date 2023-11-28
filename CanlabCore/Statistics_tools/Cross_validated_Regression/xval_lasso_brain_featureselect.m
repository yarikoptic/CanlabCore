function STATS_FINAL = xval_lasso_brain(my_outcomes, imgs, varargin)
    %STATS_FINAL = xval_lasso_brain(my_outcomes, imgs, varargin)
    %
    % PCA-Lasso based prediction on a set of brain images
    % Tor Wager, Sept. 2009
    %
    %
    % Optional inputs:
    %                 case 'reversecolors', reversecolors = 1;
    %                 case 'skipnonparam', dononparam = 0;
    %                 case 'skipsurface', dosurface = 0;
    %                 case {'cov', 'covs', 'covariates'}, covs = varargin{i+1};
    %                 case 'mask', mask = varargin{i+1}; varargin{i + 1} = [];
    %                 case 'niter', niter = varargin{i+1};
    %                 case 'more_imgs', followed by 2nd (or nth) set of
    %                 images in cell array {}
    % Example
    % -----------------------------------------------------------------------
    % mkdir LASSO_xvalidation_frontal
    % cd LASSO_xvalidation_frontal/
    % mask = '/Users/tor/Documents/Tor_Documents/CurrentExperiments/Combined_sample_2007/newmask_mapped.img';
    % load('/Users/tor/Documents/Tor_Documents/CurrentExperiments/Combined_sample_2007/robust0004/robust0001/SETUP.mat')
    % imgs = {SETUP.files};
    % my_outcomes = {SETUP.X(:, 2)};
    % covs = {SETUP.X(:, [3 4 5])};
    % outcome_name = 'Placebo Analgesia (C-P)';
    % covnames = {'Order' 'Study' 'Study x Placebo'};
    % STATS_FINAL = xval_lasso_brain(my_outcomes, imgs, 'mask', mask, 'covs', covs, 'reversecolors', 'skipsurface', 'skipnonparam');
    %
    % or
    %
    % STATS_FINAL = xval_lasso_brain(my_outcomes, imgs, 'mask', mask, 'covs', covs, 'reversecolors');

    % -----------------------------------------------------------------------
    % Optional inputs
    % -----------------------------------------------------------------------
    spm_defaults
    covs = [];
    mask = which('brainmask.nii');
    reversecolors = 0;
    dononparam = 1;
    dosurface = 1;
    niter = 200;
    covnames = {'Unknown'};
    outcome_name = 'Unknown';
    verbose = 1;
    imgs2 = {};
    dosave = 0;
    ndims = 20;
    plsstr = 'pca';
    dochoose_regparams_str = 'verbose';  % switch to 'optimize_regularization' to do inner xval
    holdout_method = 'loo'; % see xval_regression_multisubject_featureselect

    inputOptions.all_optional_inputs = varargin;

    for i = 1:length(varargin)
        if ischar(varargin{i})
            switch varargin{i}
                % Process control
                case 'reversecolors', reversecolors = 1;
                case 'skipnonparam', dononparam = 0;
                case 'skipsurface', dosurface = 0;

                    % Covariates and Masking
                case {'cov', 'covs', 'covariates'}, covs = varargin{i+1};
                case 'mask', mask = varargin{i+1}; varargin{i + 1} = [];
                case 'niter', niter = varargin{i+1};

                    % Input images
                case 'more_imgs', imgs2{end+1} = varargin{i+1};
                    fprintf('Found additional image set %3.0f\n', length(imgs2));


                    % Naming output and saving
                case 'outcome_name', outcome_name = varargin{i+1}; varargin{i + 1} = [];
                case 'covnames', covnames = varargin{i+1}; varargin{i + 1} = [];
                case 'save', dosave = 1;

                    % Dimension reduction
                case 'ndims', ndims = varargin{i+1}; varargin{i + 1} = [];
                    if strcmp(ndims, 'all')
                        ndims = size(imgs{1}, 1) - 2;
                        fprintf('Choosing %3.0f dims for PCA/PLS\n', ndims);
                    end

                case 'pca', plsstr = 'pca';  % default...
                case 'pls', plsstr = 'pls';

                    % Shrinkage/regularization parameters

                case {'choose_regparams', 'dochoose_regparams', 'optimize_regularization'}, dochoose_regparams_str = 'optimize_regularization';

                    % Holdout set selection

                case {'holdout_method'}, holdout_method = varargin{i+1}; varargin{i + 1} = [];


                case {'variable', 'verbose'} % do nothing; needed later

                otherwise, warning(['Unknown input string option:' varargin{i}]);
            end
        end
    end

    inputOptions.all_outcomes = my_outcomes;
    inputOptions.outcome_name = outcome_name;
    inputOptions.imgs = imgs;
    inputOptions.covs = covs;
    inputOptions.covnames = covnames;
    inputOptions.mask = mask;
    inputOptions.ndims = ndims;
    inputOptions.plsstr = plsstr;
    inputOptions.reversecolors = reversecolors;
    inputOptions.dochoose_regparams_str = dochoose_regparams_str;
    inputOptions.holdout_method = holdout_method;

    % set up the mask
    % -------------------------------------------------------------------------
    if isempty(mask), error('Mask is empty and/or default mask ''brainmask.nii'' cannot be found on path.'); end
    if exist(fullfile(pwd, 'mask.img')) && verbose, disp('''mask.img'' already exists in this directory.  Replacing.'); else disp('Creating mask.img'); end
    scn_map_image(mask, deblank(imgs{1}(1,:)), 'write', 'mask.img');
    maskInfo = iimg_read_img(fullfile(pwd, 'mask.img'), 2);

    inputOptions.maskInfo = maskInfo;

    datasets = length(imgs);  % each Subject would constitute a "dataset" for a multi-level/within-subjects analysis

    % load image data
    % -------------------------------------------------------------------------
    fprintf('Loading all datasets (may be memory-intensive for multi-subject fMRI): ');
    for i = 1:datasets
        fprintf('%02d', i);
        dat{i} =  iimg_get_data(maskInfo, imgs{i});
        size_orig{i} = size(dat{i});

        if ~isempty(imgs2)
            for imgset = 1:length(imgs2)
                dat{i} = [dat{i} iimg_get_data(maskInfo, imgs2{imgset}{i})];
            end

        end

    end
    fprintf('\n');

    %%

    STATS_FINAL = struct('inputOptions', inputOptions);

    % Run it: covs only
    % -------------------------------------------------------------------------
    STATS_FINAL.covs = [];
    if ~isempty(covs)
        disp('==================================')
        disp('Covariates only: OLS')
        STATS_FINAL.covs = xval_regression_multisubject_featureselect('ols', my_outcomes, covs, 'holdout_method', holdout_method);
        
        if dosave, create_figure('fitplot', 2, 2, 1); scn_export_papersetup(400); saveas(gcf, 'Lasso_xval_brain_fits_covs_only.png'); end
    end

    % Run it: data only
    % -------------------------------------------------------------------------
    if ~isempty(covs)
        disp('==================================')
        disp('Data only: lasso')
        STATS_FINAL.data = xval_regression_multisubject_featureselect('lasso', my_outcomes, dat, 'pca', 'ndims', ndims, plsstr, dochoose_regparams_str, 'holdout_method', holdout_method);
    else
        STATS_FINAL.data = 'see .full_model';
    end

    if dosave, create_figure('fitplot', 2, 2, 1); scn_export_papersetup(400); saveas(gcf, 'Lasso_xval_brain_fits_brain_only.png'); end

    % Run it: combined
    % -------------------------------------------------------------------------

    % My best guess about what will work: Lasso, with as many dims retained as possible
    % * NOTE: all of the main inputs should be cell arrays
    STATS_FINAL.full_model = [];
    if ~isempty(covs)
        disp('==================================')
        disp('Data plus covariates full model: lasso')
        STATS_FINAL.full_model = xval_regression_multisubject_featureselect('lasso', my_outcomes, dat, 'pca', 'ndims', ndims, 'covs', covs, plsstr, dochoose_regparams_str, 'holdout_method', holdout_method);
    else
        disp('Data only full model: lasso')
        disp('==================================')
        STATS_FINAL.full_model = xval_regression_multisubject_featureselect('lasso', my_outcomes, dat, 'pca', 'ndims', ndims, plsstr, dochoose_regparams_str, 'holdout_method', holdout_method);
    end

    if dosave
        save STATS_xval_output STATS_FINAL
        create_figure('fitplot', 2, 2, 1); scn_export_papersetup(400); saveas(gcf, 'Lasso_xval_brain_fits_full_model.png');
    end

    %% Figures: Scatterplot plus bars
    % -------------------------------------------------------------------------

    create_figure('Scatterplot: Full model', 1, 2);
    [r,istr,sig,h] = plot_correlation_samefig(STATS_FINAL.full_model.subjfit{1}, STATS_FINAL.inputOptions.all_outcomes{1});
    set(gca,'FontSize', 24)
    xlabel('Cross-validated prediction');
    ylabel('Outcome');
    title('Lasso cross-validation');
    set(h, 'MarkerSize', 10, 'MarkerFaceColor', [.0 .4 .8], 'LineWidth', 2);
    h = findobj(gca, 'Type', 'Text');
    set(h, 'FontSize', 24)

    % bars
    subplot(1, 2, 2)
    set(gca,'FontSize', 24)

    if ~isempty(covs)
        pevals = [std(STATS_FINAL.inputOptions.all_outcomes{1}) ...
            STATS_FINAL.full_model.pred_err_null STATS_FINAL.covs.pred_err ...
            STATS_FINAL.data.pred_err STATS_FINAL.full_model.pred_err];
        penames = {'Var(Y)' 'Mean' 'Covs' 'Brain' 'Full'};
    else
        pevals = [std(STATS_FINAL.inputOptions.all_outcomes{1}) ...
            STATS_FINAL.full_model.pred_err_null STATS_FINAL.full_model.pred_err];
        penames = {'Var(Y)' 'Mean' 'Brain'};
    end

    han = bar(pevals); set(han, 'FaceColor', [.5 .5 .5]);
    set(gca, 'XTick', 1:length(penames), 'XTickLabel', penames);
    axis tight
    ylabel('Prediction error');

    if dosave
        scn_export_papersetup(500); saveas(gcf, 'Pred_Outcome_Scatter', 'png');
    end

    % is accuracy predicted by Y and/or covariates?
    % ****


    %% NONPARAMETRIC TEST

    if dononparam

        disp('PERMUTATION TEST FOR NULL HYPOTHESIS');


        % Permute : covariates only
        % ==============================================
        if ~isempty(covs)
            clear my_outcomesp all_r pe
            ndims =  min(size(covs{1}, 2) - 1, size(covs{1}, 1) - 2); % will not work for multilevel with diff. dimensions per dataset

            fprintf('Covariates only: Running %3.0f iterations\n', niter);

            for i = 1:niter

                rand('twister',sum(100*clock)) ; % trying this; was getting wacky results suggesting randperm is not producing indep. perms...

                my_outcomes = STATS_FINAL.inputOptions.all_outcomes;

                % permute
                for s = 1:datasets
                    ix = randperm(length(my_outcomes{s}));
                    my_outcomesp{s} = my_outcomes{s}(ix);
                end

                %% Do the prediction
                % ------------------------------------------------------------------
                if size(covs, 2) > 1
                    STATSpcovs = xval_regression_multisubject_featureselect('lasso', my_outcomesp, covs, 'noverbose',  'holdout_method', holdout_method); %,'pca', 'ndims', ndims);
                else
                    STATSpcovs = xval_regression_multisubject_featureselect('ols', my_outcomesp, covs, 'noverbose',  'holdout_method', holdout_method); %,'pca', 'ndims', ndims);
                end

                fprintf('%3.2f ', STATSpcovs.r_each_subject);

                all_r(i) = STATSpcovs.r_each_subject;
                pe(i) = STATSpcovs.pred_err;

            end

            STATS_FINAL.covs.permuted.pe_values = pe;
            STATS_FINAL.covs.permuted.pe_mean = mean(pe);
            STATS_FINAL.covs.permuted.pe_ci = [prctile(pe, 5) prctile(pe, 95)];
            STATS_FINAL.covs.permuted.r_values = all_r;
            STATS_FINAL.covs.permuted.r_mean = mean(all_r);
            STATS_FINAL.covs.permuted.r_ci = [prctile(all_r, 5) prctile(all_r, 95)];
            if dosave
                save STATS_xval_output -append STATS_FINAL
                
                save STATS_xval_output_permsbackup STATS_FINAL
            end

            fprintf('\n')

        end

% %         % Permute : random subset of 1000 voxels
% %         % ==============================================
% %         n_vox = 1000;
% %         if size(dat{1}, 2) > n_vox
% %             clear my_outcomesp my_datp all_r pe
% %             ndims = size(dat{1}, 1) - 2;
% % 
% %             fprintf('1000 vox subsets: %3.0f iterations: %3.0f', niter, 0);
% % 
% %             for i = 1:niter
% % 
% %                 fprintf('\b\b\b%3.0f', i);
% % 
% %                 rand('twister',sum(100*clock)) ; % was getting wacky results suggesting randperm is not producing indep. perms...
% % 
% %                 my_outcomes = STATS_FINAL.inputOptions.all_outcomes;
% % 
% %                 % permute
% %                 for s = 1:datasets
% %                     ix = randperm(length(my_outcomes{s}));
% %                     ix2 = randperm(size(dat{s}, 2));
% % 
% %                     my_outcomesp{s} = my_outcomes{s}(ix);
% %                     my_datp{s} = dat{s}(:, ix2(1:n_vox));
% % 
% %                 end
% % 
% %                 %% Do the prediction
% %                 % ------------------------------------------------------------------
% %                 STATSpv= xval_regression_multisubject_featureselect('lasso', my_outcomesp, my_datp, 'pca', plsstr, 'ndims', ndims, dochoose_regparams_str,  'holdout_method', holdout_method, 'noverbose');
% % 
% %                 all_r(i) = STATSpv.r_each_subject;
% %                 pe(i) = STATSpv.pred_err;
% % 
% %             end
% % 
% %             fprintf('%3.2f ', all_r);
% %             fprintf('\n')
% % 
% %             STATS_FINAL.full_model.permuted.v1000_pe_values = pe;
% %             STATS_FINAL.full_model.permuted.v1000_pe_mean = mean(pe);
% %             STATS_FINAL.full_model.permuted.v1000_pe_ci = [prctile(pe, 5) prctile(pe, 95)];
% %             STATS_FINAL.full_model.permuted.v1000_r_values = all_r;
% %             STATS_FINAL.full_model.permuted.v1000_r_mean = mean(all_r);
% %             STATS_FINAL.full_model.permuted.v1000_r_ci = [prctile(all_r, 5) prctile(all_r, 95)];
% %             if dosave
% %                 save STATS_xval_output -append STATS_FINAL
% %             end
% %         end

        % Permute : Full data
        % ==============================================
        clear my_outcomesp all_r pe
        ndims = size(dat{1}, 1) - 2;

        fprintf('Full-dataset permutation: %3.0f iterations\n', niter);

        for i = 1:niter

            rand('twister',sum(100*clock)) ; % trying this; was getting wacky results suggesting randperm is not producing indep. perms...

            my_outcomes = STATS_FINAL.inputOptions.all_outcomes;

            % permute
            for s = 1:datasets
                ix = randperm(length(my_outcomes{s}));
                my_outcomesp{s} = my_outcomes{s}(ix);
            end

            %% Do the prediction
            % ------------------------------------------------------------------
            STATSp = xval_regression_multisubject_featureselect('lasso', my_outcomesp, dat, 'pca', plsstr, 'ndims', ndims,  dochoose_regparams_str, 'holdout_method', holdout_method, 'noverbose');

            fprintf('Iteration %3.0f : r = %3.2f\n', i, STATSp.r_each_subject);

            all_r(i) = STATSp.r_each_subject;
            pe(i) = STATSp.pred_err;

        end

        STATS_FINAL.full_model.permuted.pe_values = pe;
        STATS_FINAL.full_model.permuted.pe_mean = mean(pe);
        STATS_FINAL.full_model.permuted.pe_ci = [prctile(pe, 5) prctile(pe, 95)];

        STATS_FINAL.full_model.permuted.r_values = all_r;
        STATS_FINAL.full_model.permuted.r_mean = mean(all_r);
        STATS_FINAL.full_model.permuted.r_ci = [prctile(all_r, 5) prctile(all_r, 95)];
        if dosave
            save STATS_xval_output -append STATS_FINAL
        end

        % Histogram plot
        permuted_histogram_plot(STATS_FINAL);

        % turn surface off if not sig
        if STATS_FINAL.full_model.pred_err > STATS_FINAL.full_model.permuted.pe_ci(1) % not sig
            dosurface = 0;
        end
        
    end % if do nonparam

        
    % This function saves maps, plots, etc. and does a bootstrap test to
    % threshold the voxel weights.
    % It obviates the code below.
    if dosurface
        STATS_VOXWEIGHTS = xval_regression_multisubject_featureselect_bootstrapweightmap('lasso', my_outcomes, dat, maskInfo, varargin, 'pca', 'ndims', ndims, 'covs', covs, plsstr);
        save STATS_VOXWEIGHTS STATS_VOXWEIGHTS
    end
    

    
end % main function






function permuted_histogram_plot(STATS_FINAL)
    create_figure('Actual_vs_perm', 1, 2);
    set(gca, 'FontSize', 24);

    hist(STATS_FINAL.full_model.permuted.r_values, 15);
    h = findobj(gcf, 'Type', 'Patch');
    set(h, 'FaceColor', [.6 .6 .6]);
    h = plot_vertical_line(STATS_FINAL.full_model.r_each_subject); set(h, 'Color', 'r', 'LineWidth', 5);
    h = plot_vertical_line(prctile(STATS_FINAL.full_model.permuted.r_values, 95)); set(h, 'LineStyle', '--', 'LineWidth', 2);
    h = plot_vertical_line(prctile(STATS_FINAL.full_model.permuted.r_values, 5)); set(h, 'LineStyle', '--', 'LineWidth', 2);
    xlabel('Correlation: Predicted and Outcome');
    ylabel('Frequency');

    subplot(1, 2, 2)
    set(gca, 'FontSize', 24);
    hist(STATS_FINAL.full_model.permuted.pe_values, 15);
    h = findobj(gcf, 'Type', 'Patch');
    set(h, 'FaceColor', [.6 .6 .6]);
    h = plot_vertical_line(STATS_FINAL.full_model.pred_err); set(h, 'Color', 'r', 'LineWidth', 5);
    h = plot_vertical_line(prctile(STATS_FINAL.full_model.permuted.pe_values, 95)); set(h, 'LineStyle', '--', 'LineWidth', 2);
    h = plot_vertical_line(prctile(STATS_FINAL.full_model.permuted.pe_values, 5)); set(h, 'LineStyle', '--', 'LineWidth', 2);
    xlabel('Prediction error');
    ylabel('Frequency');

    scn_export_papersetup; saveas(gcf, 'Permuted_vs_actual_histograms.png');
end

        
        
% - Extra stuff -

% % %% Bootstrap the covariates
% % %
% % % This is the "Leave one out bootstrap" of Efron and Tibshirani, JASA, 1997
% % % Err(1)
% % % They show that this can be done by taking the error on each point from
% % % bootstrap samples that do not happen to contain that point
% % %
% % % they say that for continuous outcomes and predictors (our case), they
% % % expect the cross-val estimate and the 632+ bootstrap estimate to be more
% % % similar.  the benefit is mainly for discontinuous outcomes (1/0)
% % %
% % % they say that Err(1) is biased upwards compared to the nearly unbiased
% % % CV(1) (leave-one-out cross-validation)
% % % it estimates "half-sample" xval
% %
% % bootfun = @(Y, X) xval_regression_bootstrap_wrapper(Y, X);
% % STATS_FINAL.bootstrap.covs_only_r_rsq = bootstrp(200, bootfun, my_outcomes_orig{1}, covs{1});
% % STATS_FINAL.bootstrap.covs_only_summary = [mean(STATS_FINAL.bootstrap.covs_only_r_rsq) std(STATS_FINAL.bootstrap.covs_only_r_rsq) ];
% % STATS_FINAL.bootstrap.covs_only_summary_descrip = 'mean std of bootstrapped values'
% %
% % STATS_FINAL.bootstrap.dat_only_r_rsq = bootstrp(20, bootfun, my_outcomes_orig{1}, dat{1});
% %
% % STATS_FINAL.bootstrap.dat_only_r_rsq = [STATS_FINAL.bootstrap.dat_only_r_rsq; bootstrp(80, bootfun, my_outcomes_orig{1}, dat{1})];
% %
% % STATS_FINAL.bootstrap.dat_only_summary = [mean(STATS_FINAL.bootstrap.dat_only_r_rsq) std(STATS_FINAL.bootstrap.dat_only_r_rsq) ];
% % STATS_FINAL.bootstrap.dat_only_summary_descrip = 'mean std of bootstrapped values'
% %
% % %% Nonparametric test with N variables (voxels) selected at random
% %
% % s = 1;
% %
% %
% % n_vox = [1000:2000:50000];
% % niter = [1 50];
% %
% % if niter(1) == 1,  all_r_perm = zeros(niter(2), length(n_vox + 1)); end
% %
% % for i = 1:length(n_vox)
% %     for j = niter(1):niter(2)
% %
% %         rand('twister',sum(100*clock)) ; % trying this; was getting wacky results suggesting randperm is not producing indep. perms...
% %
% %         ix = randperm(length(my_outcomes{s}));
% %         ix2 = randperm(size(dat{s}, 2));
% %
% %         STATSperm= xval_regression_multisubject_featureselect('lasso', {my_outcomes{1}(ix)}, {dat{1}(:, ix2(1:n_vox(i)))}, 'pca', 'ndims', ndims);
% %
% %         all_r_perm(j, i) = STATSperm.r_each_subject;
% %
% %     end
% %
% %     create_figure('permuted');
% %     plot(n_vox(1:size(all_r_perm, 2)), mean(all_r_perm), 'ko-', 'Linewidth', 3);
% %     xlabel('Number of voxels'); ylabel('Average predicted/actual correlation');
% %     drawnow
% % end
% %
% % % with full sample
% % n_vox(end+1) = size(dat{s}, 2);
% % i = length(n_vox);
% %
% % for j = niter(1):niter(2)
% %
% %     rand('twister',sum(100*clock)) ; % trying this; was getting wacky results suggesting randperm is not producing indep. perms...
% %
% %     ix = randperm(length(my_outcomes{s}));
% %     %ix2 = randperm(size(dat{s}, 2));
% %
% %     STATSperm= xval_regression_multisubject_featureselect('lasso', {my_outcomes{1}(ix)}, dat(1), 'pca', 'ndims', ndims);
% %
% %     all_r_perm(j, i) = STATSperm.r_each_subject;
% %
% % end
% %
% % create_figure('permuted');
% % plot(n_vox(1:size(all_r_perm, 2)), mean(all_r_perm), 'ko-', 'Linewidth', 3);
% % xlabel('Number of voxels'); ylabel('Average predicted/actual correlation');
% % drawnow
