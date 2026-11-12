function fig18_dashboard()
% Figure contract: show the delivered AVM3D / single-view software,
% with the front-only lane overlay and strict match status visible.
nature_style;
out = fileparts(mfilename('fullpath'));
root = 'D:\ziguang';
paths = {
    fullfile(root,'reports','yolo3d_board_rk3568','matched_f030.png'), ...
    fullfile(root,'reports','yolo3d_nuscenes','nuscenes_matched_f048.png'), ...
    fullfile(root,'reports','launcher','quad3d_30f','quad3d_preview.png')
};
labels = {
    'a  single view: board YOLO + PC lane', ...
    'b  3D view: same-frame OBJECT', ...
    'c  four-file 3D: front inset lane'
};

fig = figure('Units','centimeters','Position',[2 2 17 10.8]);
t = tiledlayout(fig,2,2,'TileSpacing','compact','Padding','compact');

for i = 1:3
    ax = nexttile(t);
    im = imread(paths{i});
    band = max(round(0.075 * size(im,1)), 1);
    canvas = 255 * ones(size(im,1) + band, size(im,2), 3, 'uint8');
    canvas(band+1:end,:,:) = im;
    imshow(canvas,'Parent',ax);
    axis(ax,'off');
    text(ax,0.006,1 - (band/2)/size(canvas,1),labels{i}, ...
        'Units','normalized','VerticalAlignment','middle', ...
        'Color',[0.15 0.17 0.20],'FontSize',7.0, ...
        'FontWeight','bold','Interpreter','none');
end

ax = nexttile(t); axis(ax,'off'); xlim(ax,[0 10]); ylim(ax,[0 10]);
text(ax,0.2,9.1,'d  delivery evidence','FontSize',8.5,'FontWeight','bold', ...
    'Color',[0.15 0.17 0.20]);
lines = {
    'quad run: 229/229 matched';
    'queue drop: 0';
    'wait timeout: 0';
    'CRC / seq gap: 0';
    'PC throughput: 13.9 fps*';
    'PC lane: 23.3 ms';
    '* includes 1 s start delay';
    'a/b/c: different runs;';
    'not a same-run montage'
};
for k = 1:numel(lines)
    text(ax,0.3,8.0-0.8*k,lines{k},'FontSize',6.6,'Color',[0.30 0.32 0.35]);
end

exportgraphics(fig,fullfile(out,'fig18_dashboard.png'),'Resolution',600);
exportgraphics(fig,fullfile(out,'fig18_dashboard.pdf'),'ContentType','vector');
close(fig);
end
