function fig14_frame_sync()
% Figure contract: every displayed frame has a same-frame OBJECT;
% errors are counted, not hidden.
nature_style;
out = fileparts(mfilename('fullpath'));
blue = [0.20 0.44 0.65];
teal = [0.15 0.55 0.55];
gray = [0.38 0.40 0.43];
fillc = [0.93 0.95 0.96];

fig = figure('Units','centimeters','Position',[2 2 17 8.2]);
t = tiledlayout(fig,1,2,'TileSpacing','compact','Padding','compact');

ax = nexttile(t); hold(ax,'on'); axis(ax,'off');
xlim(ax,[-1.6 10]); ylim(ax,[0 10]);
n = 9;
for k = 0:n-1
    x = 0.75 + k * 1.00;
    rectangle(ax,'Position',[x 6.6 0.78 1.05],'Curvature',0.06, ...
        'FaceColor',fillc,'EdgeColor',gray,'LineWidth',0.55);
    text(ax,x+0.39,7.12,num2str(k),'HorizontalAlignment','center','FontSize',6.2);
    rectangle(ax,'Position',[x 3.55 0.78 1.05],'Curvature',0.06, ...
        'FaceColor',[0.90 0.95 0.94],'EdgeColor',teal,'LineWidth',0.55);
    text(ax,x+0.39,4.07,num2str(k),'HorizontalAlignment','center','FontSize',6.2);
    arrow(ax,x+0.39,6.55,x+0.39,4.65);
end
text(ax,-0.15,7.15,'video','HorizontalAlignment','right','FontSize',6.5,'Color',gray);
text(ax,-0.15,4.10,'OBJECT','HorizontalAlignment','right','FontSize',6.5,'Color',teal);
text(ax,5.0,9.30,'a  strict frame_id alignment','HorizontalAlignment','center', ...
    'FontSize',8.5,'FontWeight','bold','Color',[0.15 0.17 0.20]);
text(ax,5.0,1.55,'same frame_id required; no nearest-time fallback', ...
    'HorizontalAlignment','center','FontSize',6.3,'Color',gray);
text(ax,5.0,0.95,'quad 229/229  |  single 1852/1852', ...
    'HorizontalAlignment','center','FontSize',6.5,'Color',blue,'FontWeight','bold');

ax2 = nexttile(t); hold(ax2,'on');
barh(ax2,[2 1],[1 1],0.42,'FaceColor',teal,'EdgeColor','none');
xlim(ax2,[0 1.08]); ylim(ax2,[0.55 2.55]);
set(ax2,'YTick',[1 2],'YTickLabel',{'single 1852','quad 229'},'FontSize',7);
xlabel(ax2,'matched fraction','FontSize',7);
text(ax2,0.50,1,'100%','HorizontalAlignment','center','FontSize',7,'Color','w', ...
    'FontWeight','bold');
text(ax2,0.50,2,'100%','HorizontalAlignment','center','FontSize',7,'Color','w', ...
    'FontWeight','bold');
text(ax2,1.02,1,'1852/1852','FontSize',6.4,'Color',teal);
text(ax2,1.02,2,'229/229','FontSize',6.4,'Color',teal);
text(ax2,0.54,2.45,'b  matched-frame rate','HorizontalAlignment','center', ...
    'FontSize',8.5,'FontWeight','bold','Color',[0.15 0.17 0.20]);
text(ax2,0.02,0.69,'0 queue drop  ·  0 wait timeout  ·  0 CRC/seq gap', ...
    'HorizontalAlignment','left','FontSize',6.1,'Color',gray);

exportgraphics(fig,fullfile(out,'fig14_frame_sync.png'),'Resolution',600);
exportgraphics(fig,fullfile(out,'fig14_frame_sync.pdf'),'ContentType','vector');
close(fig);
end

function arrow(ax,x1,y1,x2,y2)
quiver(ax,x1,y1,x2-x1,y2-y1,0,'Color',[0.42 0.44 0.47], ...
    'LineWidth',0.6,'MaxHeadSize',0.65);
end
