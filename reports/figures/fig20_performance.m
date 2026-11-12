function fig20_performance()
% Figure contract: RK/PC latency and throughput stay inside the 15 fps budget;
% temperature is deliberately omitted because it was not logged.
nature_style;
out = fileparts(mfilename('fullpath'));
blue = [0.20 0.44 0.65];
teal = [0.15 0.55 0.55];
amber = [0.78 0.55 0.18];
gray = [0.38 0.40 0.43];

fig = figure('Units','centimeters','Position',[2 2 17 8.2]);
t = tiledlayout(fig,1,2,'TileSpacing','compact','Padding','compact');

ax = nexttile(t); hold(ax,'on');
vals = [16.97 18.46 50.39];
b = bar(ax,vals,0.52,'FaceColor',blue,'EdgeColor','none');
b.FaceColor = 'flat';
b.CData(1,:) = blue; b.CData(2,:) = teal; b.CData(3,:) = amber;
set(ax,'XTick',1:3,'XTickLabel',{'P50','P95','max'},'FontSize',7);
ylabel(ax,'PC render time (ms)','FontSize',7);
xlim(ax,[0.35 3.65]); ylim(ax,[0 70]);
yline(ax,66.7,'--','15 fps budget','LabelVerticalAlignment','bottom', ...
    'Color',[0.45 0.47 0.50],'FontSize',6.4,'LineWidth',0.7);
for i = 1:3
    text(ax,i,vals(i)+2.2,sprintf('%.1f',vals(i)), ...
        'HorizontalAlignment','center','FontSize',6.6,'Color',[0.20 0.22 0.25]);
end
title(ax,'a  PC render time (229 frames)','FontSize',8.5,'FontWeight','bold', ...
    'Color',[0.15 0.17 0.20]);

ax2 = nexttile(t); hold(ax2,'on');
fps = [15.00 16.16 13.95];
b2 = bar(ax2,fps,0.52,'FaceColor',teal,'EdgeColor','none');
b2.FaceColor = 'flat';
b2.CData(1,:) = teal; b2.CData(2,:) = blue; b2.CData(3,:) = amber;
set(ax2,'XTick',1:3,'XTickLabel',{'board 15','board max','PC 229'}, ...
    'FontSize',7);
ylabel(ax2,'throughput (fps)','FontSize',7);
xlim(ax2,[0.35 3.65]); ylim(ax2,[0 18]);
for i = 1:3
    text(ax2,i,fps(i)+0.45,sprintf('%.2f',fps(i)), ...
        'HorizontalAlignment','center','FontSize',6.6,'Color',[0.20 0.22 0.25]);
end
title(ax2,'b  throughput','FontSize',8.5,'FontWeight','bold', ...
    'Color',[0.15 0.17 0.20]);
text(ax2,0.55,17.25,'229/229 matched · 0 queue drop · 0 wait timeout', ...
    'HorizontalAlignment','left','FontSize',6.1,'Color',gray);
text(ax2,0.55,16.55,'temperature not logged','HorizontalAlignment','left', ...
    'FontSize',6.0,'Color',gray);

exportgraphics(fig,fullfile(out,'fig20_performance.png'),'Resolution',600);
exportgraphics(fig,fullfile(out,'fig20_performance.pdf'),'ContentType','vector');
close(fig);
end
