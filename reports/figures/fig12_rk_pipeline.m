function fig12_rk_pipeline()
% Figure contract: RK3568 front-only inference fits the 15 fps budget.
% Panel a: deployment/pipeline; panel b: measured single-frame budget.
nature_style;
out = fileparts(mfilename('fullpath'));
blue = [0.20 0.44 0.65];
teal = [0.15 0.55 0.55];
amber = [0.78 0.55 0.18];
gray = [0.38 0.40 0.43];
fillc = [0.93 0.95 0.96];

fig = figure('Units','centimeters','Position',[2 2 17 8.6]);
t = tiledlayout(fig,1,2,'TileSpacing','compact','Padding','compact');

% ---------------- panel a: pipeline
ax = nexttile(t); hold(ax,'on'); axis(ax,'off');
xlim(ax,[0 10]); ylim(ax,[0 10]);

boxes = {
    [0.20 6.60 2.00 1.55], 'Source', 'FILE / HDMI';
    [2.85 6.60 2.35 1.55], 'Preprocess', 'resize + pad';
    [5.85 6.60 1.85 1.55], 'RKNN', 'split6 640';
    [8.15 6.60 1.65 1.55], 'Post', 'DFL/NMS';
    [8.15 2.45 1.65 1.55], 'OBJECT', 'UDP 7000';
    [5.55 2.45 2.25 1.55], 'PC store', 'frame_id';
    [2.85 2.45 2.30 1.55], 'AVM3D', 'single / 3D';
    [0.20 2.45 2.00 1.55], 'Contract', '640x360';
};
for i = 1:size(boxes,1)
    rectangle(ax,'Position',boxes{i,1},'Curvature',0.08, ...
        'FaceColor',fillc,'EdgeColor',gray,'LineWidth',0.6);
    text(ax,boxes{i,1}(1)+boxes{i,1}(3)/2,boxes{i,1}(2)+boxes{i,1}(4)*0.64, ...
        boxes{i,2},'HorizontalAlignment','center','FontSize',7,'FontWeight','bold', ...
        'Color',[0.15 0.17 0.20]);
    text(ax,boxes{i,1}(1)+boxes{i,1}(3)/2,boxes{i,1}(2)+boxes{i,1}(4)*0.28, ...
        boxes{i,3},'HorizontalAlignment','center','FontSize',5.8,'Color',gray);
end

arrow(ax,2.20,7.38,2.85,7.38);
arrow(ax,5.20,7.38,5.85,7.38);
arrow(ax,7.70,7.38,8.15,7.38);
arrow(ax,8.98,6.60,8.98,4.00);
arrow(ax,8.15,3.23,7.80,3.23);
arrow(ax,5.55,3.23,5.15,3.23);
arrow(ax,2.85,3.23,2.20,3.23);

text(ax,1.25,5.95,'pre 2.0 ms','HorizontalAlignment','center','FontSize',6.2,'Color',blue);
text(ax,4.00,5.95,'infer 44.0 ms','HorizontalAlignment','center','FontSize',6.2,'Color',blue);
text(ax,7.00,5.95,'post 9.5 ms','HorizontalAlignment','center','FontSize',6.2,'Color',blue);
text(ax,5.0,9.45,'a  RK3568 front-only inference','HorizontalAlignment','center', ...
    'FontSize',8.5,'FontWeight','bold','Color',[0.15 0.17 0.20]);
text(ax,9.95,0.35,'typical measured values; log-sampled','HorizontalAlignment','right', ...
    'FontSize',6,'Color',gray);

% ---------------- panel b: budget
ax2 = nexttile(t); hold(ax2,'on');
vals = [2.0 44.0 9.5];
b = barh(ax2,1,vals,'stacked','EdgeColor','none','BarWidth',0.50);
b(1).FaceColor = blue; b(2).FaceColor = teal; b(3).FaceColor = amber;
xlim(ax2,[0 72]); ylim(ax2,[0.45 1.55]);
set(ax2,'YTick',[]);
xlabel(ax2,'Latency per frame (ms)','FontSize',7);
xline(ax2,66.7,'--','Color',[0.45 0.47 0.50],'LineWidth',0.7);
title(ax2,'b  Single-frame budget','FontSize',8.5,'FontWeight','bold', ...
    'Color',[0.15 0.17 0.20]);
text(ax2,20.0,1.00,'44.0','HorizontalAlignment','center','FontSize',6.4, ...
    'Color','w','FontWeight','bold');
text(ax2,53.0,1.00,'9.5','HorizontalAlignment','center','FontSize',6.4, ...
    'Color','w','FontWeight','bold');
text(ax2,2.0,0.66,'2.0','HorizontalAlignment','center','FontSize',6.2,'Color',blue);
text(ax2,3.0,0.54,'pre','FontSize',6.2,'Color',blue);
text(ax2,20.0,0.54,'infer','FontSize',6.2,'Color',teal);
text(ax2,57.0,0.54,'post','FontSize',6.2,'Color',amber);
text(ax2,38.0,1.47,'total 55.5 ms','HorizontalAlignment','center', ...
    'FontSize',6.5,'Color',[0.20 0.22 0.25]);
text(ax2,71.5,1.47,'15 fps budget','HorizontalAlignment','right', ...
    'FontSize',6.2,'Color',[0.45 0.47 0.50]);

exportgraphics(fig,fullfile(out,'fig12_rk_pipeline.png'),'Resolution',600);
exportgraphics(fig,fullfile(out,'fig12_rk_pipeline.pdf'),'ContentType','vector');
close(fig);
end

function arrow(ax,x1,y1,x2,y2)
quiver(ax,x1,y1,x2-x1,y2-y1,0,'Color',[0.42 0.44 0.47], ...
    'LineWidth',0.7,'MaxHeadSize',0.60);
end
