import tabs.Tab;
import research;
import icons;
import util.formatting;
import elements.BaseGuiElement;
import elements.GuiSkinElement;
import elements.GuiMarkupText;
import elements.MarkupTooltip;
import elements.GuiText;
import elements.GuiSprite;
import elements.GuiPanel;
import elements.GuiButton;
import elements.GuiOverlay;
import elements.GuiListbox;
import elements.GuiIconGrid;
import elements.GuiBackgroundPanel;
import elements.GuiProgressbar;
import elements.GuiContextMenu;
import editor.completion;
import editor.locale;
from gui import animate_time, navigateInto, animate_speed, animate_remove, animate_snap;
from tabs.tabbar import newTab, switchToTab;

Tab@ createResearchTab() {
	return ResearchTab();
}

const vec2i T_SIZE(201, 134);
const uint T_SPAC = 27;
const uint T_OFF = 10;
const uint T_IMG = 134 - T_OFF*2 - 30;
const uint TT_WIDTH = 400;

class TechDisplay : BaseGuiElement {
	TechnologyNode node;
	const TechnologyType@ prevType;
	bool hovered = false;
	bool selected = false;
	GuiMarkupText@ description;
	GuiMarkupText@ cost;
	GuiProgressbar@ timer;
	bool canUnlock = false;
	double zoom = 1.0;
	uint adjacent = 0;
	bool haveAdjQueued = false;

	TechDisplay(IGuiElement@ parent) {
		super(parent, recti());

		@description = GuiMarkupText(this, Alignment(Left+10, Top+T_OFF+25, Right-10, Bottom-T_OFF));
		description.defaultStroke = colors::Black;
		@cost = GuiMarkupText(this, Alignment(Left+10, Bottom-25-T_OFF, Right-10, Bottom-T_OFF));
		cost.defaultStroke = colors::Black;
		@timer = GuiProgressbar(this, Alignment(Left+0.25f, Bottom-25-T_OFF, Right-0.25f, Bottom-T_OFF));
		timer.visible = false;
	}

	void update(double zoom = 1.0) {
		this.zoom = zoom;
		vec2i pos;
		pos.x = double(node.position.x * T_SIZE.x) * zoom;
		pos.y = double(node.position.y * (T_SIZE.y - T_SPAC)) * zoom;
		if(node.position.y % 2 != 0)
			pos.x += double(T_SIZE.x / 2) * zoom;
		pos.x -= double(T_SIZE.x / 2) * zoom;
		pos.y -= double(T_SIZE.y / 2) * zoom;

		size = vec2i(double(T_SIZE.x) * zoom, double(T_SIZE.y) * zoom);
		position = pos;

		canUnlock = node.canUnlock(playerEmpire);
		bool isBig = node.type.cls >= Tech_Unlock;
		cost.visible = !node.bought && !node.queued && (node.available || haveAdjQueued) && zoom >= 0.8;
		description.visible = !node.bought && !node.queued && zoom >= 0.8 && canUnlock && isBig;
		timer.visible = node.timer >= 0.01 && zoom >= 0.8;

		if(!canUnlock)
			description.defaultColor = Color(0x909090ff);
		else
			description.defaultColor = Color(0xffffffff);

		if(node.timer >= 0.0) {
			auto totalTime = node.getTimeCost();
			if(totalTime > 0) {
				timer.progress = (totalTime - node.timer) / totalTime;
				timer.text = formatTime(node.timer / playerEmpire.ResearchUnlockSpeed);
			}
			else {
				timer.visible = false;
			}
		}

		if(prevType !is node.type) {
			description.text = format("[center]$1[/center]", node.type.blurb);
			@prevType = node.type;

			string costText = "";
			bool haveSecondary = false;

			if(playerEmpire.ForbidSecondaryUnlock == 0) {
				costText = node.getSecondaryCost(playerEmpire);
				haveSecondary = costText.length != 0;
			}

			if(node.type.pointCost != 0) {
				if(costText.length != 0)
					costText = format(" [color=#888]$1[/color] ", locale::RESEARCH_COST_OR)+costText;
				costText = format("[img=$1;$4/][color=$2][b]$3[/b][/color]",
					getSpriteDesc(icons::Research), toString(colors::Research),
					toString(node.type.pointCost, 0), haveSecondary?"20":"30")+costText;
			}

			if(!haveSecondary)
				cost.defaultFont = FT_Medium;
			else
				cost.defaultFont = FT_Normal;
			cost.text = format("[center]$1[/center]", costText);
			timer.frontColor = node.type.color;
		}
	}

	bool onGuiEvent(const GuiEvent& event) {
		switch(event.type) {
			case GUI_Mouse_Entered:
				if(event.caller is this) {
					hovered = true;
					emitHoverChanged();
				}
			break;
			case GUI_Mouse_Left:
				if(event.caller is this) {
					hovered = false;
					emitHoverChanged();
				}
			break;
		}
		return BaseGuiElement::onGuiEvent(event);
	}

	bool onMouseEvent(const MouseEvent& event, IGuiElement@ source) {
		if(event.type == MET_Button_Up && isAncestorOf(source)) {
			emitClicked(event.button);
			return true;
		}
		return BaseGuiElement::onMouseEvent(event, source);
	}

	IGuiElement@ elementFromPosition(const vec2i& pos) override {
		IGuiElement@ elem = BaseGuiElement::elementFromPosition(pos);
		if(elem is this) {
			vec2i relPos = pos-AbsolutePosition.topLeft;
			relPos.x = double(relPos.x) / zoom;
			relPos.y = double(relPos.y) / zoom;
			if(!techBase.isPixelActive(0, relPos))
				return null;
		}
		return elem;
	}

	const SpriteSheet@ get_techBase() {
		if(node.type !is null) {
			if(node.type.cls == Tech_Boost)
				return spritesheet::TechBoost;
			if(node.type.cls == Tech_Unlock)
				return spritesheet::TechUnlock;
			if(node.type.cls == Tech_Keystone)
				return spritesheet::TechKeystone;
		}
		return spritesheet::TechBase;
	}

	void cacheGrid(TechnologyGrid& grid) {
		adjacent = 0;
		haveAdjQueued = false;
		for(uint i = 0; i < 6; ++i) {
			auto@ other = grid.getAdjacentNode(node.position, i);
			if(other !is null) {
				adjacent |= 1<<i;
				if(other.queued)
					haveAdjQueued = true;
			}
		}
	}

	void drawBeams(ResearchTab& tab, TechnologyGrid& grid) {
		vec2i origin = absolutePosition.center;
		for(uint i = 0; i < 3; ++i) {
			if(adjacent & (1<<i) != 0) {
				auto@ other = tab.getAdjacent(this, i);
				if(other !is null) {
					Color beamColor = Color(0xffffffff);
					const Material@ mat = material::LockedResearchBeam;
					if((other.node.available && node.bought) || (node.available && other.node.bought))
						@mat = material::ResearchBeam;

					vec2i targ = other.absolutePosition.center;
					drawLine(origin, targ, beamColor, 18.0 * tab.zoom, mat);
				}
			}
		}
	}

	void draw() {
		if(node.type is null)
			return;

		bool canUnlock = node.canUnlock(playerEmpire);
		uint index = 0;
		if(node.bought || node.queued)
			index = 1;
		else if(canUnlock)
			index = 0;
		else
			index = 2;

		auto@ base = techBase;

		Color col = node.type.color;
		if(node.type.cls != Tech_Special) {
			if(node.timer >= 0.01) {
				(base+index).draw(AbsolutePosition);

				shader::PROGRESS = timer.progress;
				shader::DIM_FACTOR = 0.f;
				(base+index).draw(AbsolutePosition, col, shader::RadialDimmed);
			}
			else if(node.unlocked) {
				shader::SATURATION_LEVEL = 0.05f;
				(base+index).draw(AbsolutePosition,
						col.interpolate(Color(0x808080ff), 0.5f), shader::Desaturate);
			}
			else if(canUnlock) {
				(base+index).draw(AbsolutePosition, col);
			}
			else {
				shader::SATURATION_LEVEL = 0.05f;
				(base+index).draw(AbsolutePosition,
						col.interpolate(Color(0x808080ff), 0.75f), shader::Desaturate);
			}
			if(hovered)
				(base+3).draw(AbsolutePosition, col);
			if(selected)
				(base+4).draw(AbsolutePosition, col);
		}

		Sprite icon = node.type.icon;
		if(icon.valid) {
			recti iconPos;

			double iconPct = 0.33;
			if(node.type.cls >= Tech_Unlock)
				iconPct = 0.5;
			if(node.type.cls >= Tech_Special)
				iconPct = 1.0;
			iconPos = recti_centered(AbsolutePosition, size*iconPct);

			vec2i isize = icon.size;
			if(isize.y != 0)
				iconPos = iconPos.aspectAligned(double(isize.x) / double(isize.y));

			if(node.timer >= 0.01) {
				shader::SATURATION_LEVEL = 0.f;
				Sprite bg = icon;
				bg.color = Color(0xffffffff);
				bg.draw(iconPos, colors::White, shader::Desaturate);

				shader::PROGRESS = timer.progress;
				shader::DIM_FACTOR = 0.f;
				icon.draw(iconPos, colors::White, shader::RadialDimmed);
			}
			else if(node.unlocked && node.type.cls != Tech_Special) {
				shader::SATURATION_LEVEL = 0.f;
				Sprite bg = icon;
				bg.color = Color(0xffffffff);
				bg.draw(iconPos, colors::White, shader::Desaturate);
			}
			else if(canUnlock || hovered) {
				icon.draw(iconPos);
			}
			else {
				if(node.type.cls >= Tech_Unlock) {
					shader::SATURATION_LEVEL = 0.2f;
					icon.color = icon.color.interpolate(Color(0xffffffaa), 0.75f);
				}
				else {
					shader::SATURATION_LEVEL = 0.f;
					icon.color = Color(0xffffffaa);
				}
				if(zoom < 0.6)
					shader::SATURATION_LEVEL += 0.3f;
				icon.draw(iconPos, colors::White, shader::Desaturate);
			}
		}

		if(zoom >= 0.4 && (!node.unlocked || node.type.cls >= Tech_Keystone) && (canUnlock || (haveAdjQueued && !node.queued) || node.type.cls >= Tech_Unlock) && node.timer < 0.01) {
			Color titleColor = node.type.color;
			/*if(!canUnlock)*/
			/*	titleColor = titleColor.interpolate(Color(0x808080ff), 0.8f);*/

			const Font@ ft = skin.getFont(FT_Medium);
			bool enough = ft.getDimension(node.type.name).x < size.width-20;

			if(!enough || node.type.cls < Tech_Unlock) {
				@ft = skin.getFont(FT_Subtitle);
				enough = ft.getDimension(node.type.name).x < size.width-20;
			}
			if(!enough) {
				@ft = skin.getFont(FT_Bold);
				enough = ft.getDimension(node.type.name).x < size.width-20;
			}
			if(!enough)
				@ft = skin.getFont(FT_Small);

			ft.draw(
				pos=recti_area(10,T_OFF, size.width-20,30)+absolutePosition.topLeft,
				text=node.type.name,
				stroke=colors::Black,
				color=titleColor,
				horizAlign=0.5,
				vertAlign=0.0);
		}

		BaseGuiElement::draw();
	}
};

class TechTooltip : BaseGuiElement {
	GuiMarkupText@ description;
	TechDisplay@ tied;

	GuiButton@ researchButton;
	GuiMarkupText@ researchText;

	GuiButton@ secondaryButton;
	GuiMarkupText@ secondaryText;
	
	TechTooltip(IGuiElement@ parent) {
		super(parent, recti());

		@description = GuiMarkupText(this, recti_area(12,12,TT_WIDTH-24,300));

		@researchButton = GuiButton(this, Alignment(Left+0.5f-110, Bottom-52, Width=220, Height=40));
		researchButton.color = colors::Research;
		@researchText = GuiMarkupText(researchButton, Alignment().padded(-1,8,0,4));
		researchText.defaultFont = FT_Bold;

		@secondaryButton = GuiButton(this, Alignment(Left+0.5f-110, Bottom-52-46, Width=220, Height=40));
		@secondaryText = GuiMarkupText(secondaryButton, Alignment().padded(0,8,0,4));
		secondaryText.defaultFont = FT_Bold;
	}

	void updateAbsolutePosition() {
		if(tied !is null) {
			if(researchButton.visible)
				secondaryButton.alignment.top.pixels = 52+46;
			else
				secondaryButton.alignment.top.pixels = 52;
		}
		BaseGuiElement::updateAbsolutePosition();
		if(tied is null)
			return;
		int h = 24;
		if(researchButton.visible)
			h += 46;
		if(secondaryButton.visible)
			h += 46;
		size = vec2i(TT_WIDTH, description.size.height+h);

		vec2i pos = vec2i(tied.position.x+tied.size.x, tied.position.y+tied.size.y/2-size.y/2);
		position = pos;
		if(absolutePosition.botRight.x > parent.absolutePosition.botRight.x) {
			pos.x = tied.position.x - size.width - 8;
			position = pos;
		}
		if(absolutePosition.topLeft.y < parent.absolutePosition.topLeft.y) {
			pos.y += (parent.absolutePosition.topLeft.y - absolutePosition.topLeft.y);
			position = pos;
		}
		else if(absolutePosition.botRight.y > parent.absolutePosition.botRight.y) {
			pos.y += (parent.absolutePosition.botRight.y - absolutePosition.botRight.y);
			position = pos;
		}
	}


	bool onGuiEvent(const GuiEvent& event) {
		if(event.caller is researchButton && event.type == GUI_Clicked) {
			if(tied.node.queued)
				playerEmpire.setResearchQueued(tied.node.id, false);
			else
				playerEmpire.research(tied.node.id, queue=true);
			emitClicked();
			return true;
		}
		else if(event.caller is secondaryButton && event.type == GUI_Clicked) {
			playerEmpire.research(tied.node.id, secondary=true);
			emitClicked();
			return true;
		}
		return BaseGuiElement::onGuiEvent(event);
	}

	void update(double time) {
		if(tied is null)
			return;

		bool canUnlock = tied.node.canUnlock(playerEmpire);
		auto@ type = tied.node.type;
		auto cost = tied.node.getPointCost(playerEmpire);

		if(cost > 0 && !tied.node.bought) {
			if(tied.node.queued) {
				researchButton.visible = true;
				researchButton.disabled = false;
				researchButton.color = colors::Research;
				researchText.text = format("[center]$1[/center]",
						locale::UNQUEUE_RESEARCH, toString(cost, 0),
						getSpriteDesc(icons::Research), toString(colors::Research));
			}
			else if(tied.node.available && canUnlock && playerEmpire.ResearchPoints >= cost) {
				researchButton.visible = true;
				researchButton.disabled = false;
				researchButton.color = colors::Research;
				researchText.text = format("[center]$1: [img=$3;20/][color=$4]$2[/color][/center]",
						locale::RESOURCE_RESEARCH, toString(cost, 0),
						getSpriteDesc(icons::Research), toString(colors::Research));
			}
			else if(tied.haveAdjQueued || tied.node.available) {
				researchButton.visible = true;
				researchButton.disabled = false;
				researchButton.color = colors::Research;
				researchText.text = format("[center]$1: [img=$3;20/][color=$4]$2[/color][/center]",
						locale::QUEUE_RESEARCH, toString(cost, 0),
						getSpriteDesc(icons::Research), toString(colors::Research));
			}
			else {
				researchButton.visible = false;
			}
		}
		else {
			researchButton.visible = false;
		}

		string sec;
		if(playerEmpire.ForbidSecondaryUnlock == 0)
			sec = tied.node.getSecondaryCost(playerEmpire);
		if(sec.length != 0) {
			secondaryButton.color = type.color;
			secondaryText.text = format("[center]$1: $2[/center]", type.secondaryTerm, sec);
			secondaryButton.visible = !tied.node.bought && !tied.node.queued && canUnlock;
			secondaryButton.disabled = !tied.node.canSecondaryUnlock(playerEmpire);
		}
		else {
			secondaryButton.visible = false;
		}
	}

	void update(TechDisplay@ tech) {
		@tied = tech;

		auto@ type = tied.node.type;
		string desc = type.description;

		auto cost = tied.node.getPointCost(playerEmpire);
		if(cost > 0) {
			desc += format("\n\n[img=$1;20/] [b]$2[/b]: [offset=200]$3[/offset]",
					getSpriteDesc(icons::Research), locale::RESEARCH_COST, toString(cost,0));
		}

		auto time = tied.node.getTimeCost(playerEmpire) / playerEmpire.ResearchUnlockSpeed;
		if(time > 0.01) {
			if(cost <= 0)
				desc += "\n";
			desc += format("\n[img=$1;20/] [b]$2[/b]: [offset=200]$3[/offset]",
					getSpriteDesc(icons::Duration), locale::RESEARCH_TIME, formatTime(time));
		}

		description.text = format(
			"[font=Medium][color=$2]$1[/color][/font]\n\n$3",
			type.name, toString(type.color), desc);


		update(0.0);
		parent.updateAbsolutePosition();
	}

	void draw() {
		skin.draw(SS_Panel, SF_Normal, AbsolutePosition);
		BaseGuiElement::draw();
		if(tied !is null){
			Color col = tied.node.type.color;
			col.a = 0x20;
			drawRectangle(recti_area(5,12,TT_WIDTH-13,32)+AbsolutePosition.topLeft, Color(col));
		}
	}
};

class ResearchTab : Tab {
	GuiPanel@ panel;
	array<TechDisplay@> techs;

	TechTooltip@ ttip;
	TechDisplay@ selected;
	double zoom = 1.0;
	TechnologyGrid grid;

	ResearchTab() {
		title = locale::RESEARCH;

		@panel = GuiPanel(this, Alignment(Left, Top, Right, Bottom));
		panel.setScrollPane(true);
		panel.dragThreshold = 10;
		panel.allowScrollDrag = false;
		panel.sizePadding = recti(100, 300, 600, 300);

		@ttip = TechTooltip(panel);
	}

	void show() override {
		update();
		Tab::show();
	}
	
	Color get_activeColor() {
		return Color(0xd482ffff);
	}

	Color get_inactiveColor() {
		return Color(0xa800ffff);
	}

	Color get_seperatorColor() {
		return Color(0x75488dff);
	}	

	TabCategory get_category() {
		return TC_Research;
	}

	Sprite get_icon() {
		return Sprite(material::TabResearch);
	}

	TechDisplay@ getAdjacent(TechDisplay@ from, uint adj) {
		vec2i pos = from.node.position;
		if(!grid.doAdvance(pos, HexGridAdjacency(adj)))
			return null;
		int index = grid.getIndex(pos);
		if(index == -1)
			return null;
		return techs[index];
	}

	void update() {
		auto@ dat = playerEmpire.getTechnologyNodes();
		uint index = 0;
		uint prevCnt = techs.length;
		grid.nodes.length = 0;
		while(true) {
			if(index >= techs.length)
				techs.insertLast(TechDisplay(panel));

			if(!receive(dat, techs[index].node))
				break;

			grid.nodes.insertLast(techs[index].node);
			techs[index].update(zoom);
			++index;
		}
		for(uint i = index, cnt = techs.length; i < cnt; ++i)
			techs[i].remove();
		grid.regenBounds();
		for(uint i = 0, cnt = techs.length; i < cnt; ++i)
			techs[i].cacheGrid(grid);
		techs.length = index;
		if(prevCnt == 0)
			panel.centerAround(vec2i(0,0));
		ttip.bringToFront();
	}

	void updatePositions() {
		for(uint i = 0, cnt = techs.length; i < cnt; ++i)
			techs[i].update(zoom);
	}

	void updateAbsolutePosition() {
		Tab::updateAbsolutePosition();

		double w = size.width, h = size.height;
		panel.minPanelSize = recti(-w,-h, w,h);

		update();
	}

	double timer = 0;
	void tick(double time) override {
		if(!visible)
			return;

		timer += time;
		if(timer >= 1.0) {
			if(ttip !is null && ttip.visible)
				ttip.update(timer);
			update();
			timer = 0;
		}
		if(!panel.isDragging && settings::bResearchEdgePan && windowFocused && mouseOverWindow) {
			if(mousePos.x <= 2) {
				panel.scroll(+1000.0 * time, 0);
			}
			else if(mousePos.x >= screenSize.width - 2) {
				panel.scroll(-1000.0 * time, 0);
			}
			if(mousePos.y <= 2) {
				panel.scroll(0, +1000.0 * time);
			}
			else if(mousePos.y >= screenSize.height - 2) {
				panel.scroll(0, -1000.0 * time);
			}
		}
	}

	void draw() override {
		skin.draw(SS_ResearchBG, SF_Normal, AbsolutePosition);
		for(uint i = 0, cnt = techs.length; i < cnt; ++i)
			techs[i].drawBeams(this, grid);
		Tab::draw();
	}

	bool onMouseEvent(const MouseEvent& event, IGuiElement@ source) {
		if(event.type == MET_Button_Up && event.button == 0 && !ttip.isAncestorOf(source)) {
			if(selected !is null) {
				selected.selected = false;
				@selected = null;
			}
			ttip.visible = false;
			panel.stopDrag();
			return true;
		}
		if(event.type == MET_Scrolled) {
			//Keep position under cursor constant
			vec2i mOff = mousePos - panel.absolutePosition.topLeft;

			double prevZoom = zoom;
			zoom = clamp(zoom + double(event.y) * 0.2, 0.2, 1.0);

			panel.scrollOffset.x = (zoom * double(mOff.x + panel.scrollOffset.x)) / prevZoom - mOff.x;
			panel.scrollOffset.y = (zoom * double(mOff.y + panel.scrollOffset.y)) / prevZoom - mOff.y;

			updatePositions();
			panel.updateAbsolutePosition();
			panel.updateAbsolutePosition();
			return true;
		}
		return BaseGuiElement::onMouseEvent(event, source);
	}

	bool onGuiEvent(const GuiEvent& event) {
		if(event.type == GUI_Hover_Changed) {
			auto@ disp = cast<TechDisplay>(event.caller);
			if(disp !is null && selected is null) {
				if(!disp.hovered && disp is ttip.tied) {
					ttip.visible = false;
				}
				else {
					ttip.update(disp);
					ttip.visible = true;
				}
				return true;
			}
		}
		else if(event.type == GUI_Clicked) {
			if(event.caller is ttip) {
				update();
				timer = 0.3;
				ttip.visible = false;
				if(selected !is null) {
					selected.selected = false;
					@selected = null;
				}
				return true;
			}
			else if(event.value == 0 || event.value == 2) {
				auto@ disp = cast<TechDisplay>(event.caller);
				if(disp !is null) {
					if(!panel.isDragging) {
						if(selected !is null)
							selected.selected = false;
						if(disp.canUnlock || disp.haveAdjQueued) {
							if(ctrlKey) {
								playerEmpire.research(disp.node.id, queue=true);
								update();
								timer = 0.3;
							}
							else if(selected !is disp) {
								@selected = disp;
								selected.selected = true;
								ttip.update(disp);
								ttip.visible = true;
							}
							else {
								@selected = null;
								ttip.visible = false;
							}
						}
					}
					panel.stopDrag();
					return true;
				}
			}
		}
		return BaseGuiElement::onGuiEvent(event);
	}
};

class ResearchEditor : ResearchTab {
	bool created = false;
	vec2i hovered(INT_MAX,INT_MAX);

	ResearchEditor() {
		super();
		panel.minPanelSize = recti(-20000,-20000, 20000,20000);
	}

	void show() {
		created = false;
		update();
		Tab::show();
	}

	Completion@ getCompletion(const string& ident) {
		for(uint i = 0, cnt = techCompletions.length; i < cnt; ++i) {
			if(techCompletions[i].ident == ident) {
				return techCompletions[i];
			}
		}
		return null;
	}

	TechnologyType@ makeType(Completion@ compl) {
		TechnologyType type;
		type.ident = compl.ident;
		type.name = compl.name;
		type.description = compl.longDescription;
		if(compl.description.length < 30)
			type.blurb = compl.description;
		type.icon = compl.icon;
		type.color = compl.color;
		return type;
	}

	void updateAbsolutePosition() {
		Tab::updateAbsolutePosition();
		update();
	}

	void update() {
		if(!created) {
			created = true;
			initCompletions();
			uint prevCnt = techs.length;

			for(uint i = 0, cnt = techs.length; i < cnt; ++i)
				techs[i].remove();
			techs.length = 0;

			const string fname = resolve("data/research/base_grid.txt");
			ReadFile file(fname, true);
			while(file++) {
				if(file.key != "Grid") {
					vec2i pos;
					int xp = file.value.findFirst(",");
					if(xp == -1) {
						pos.x = toInt(file.value);
					}
					else {
						pos.x = toInt(file.value.substr(0,xp));
						pos.y = toInt(file.value.substr(xp+1));
					}

					Completion@ compl = getCompletion(file.key);
					if(compl !is null) {
						TechDisplay disp(panel);
						@disp.node.type = makeType(compl);
						disp.node.unlocked = false;
						disp.node.bought = false;
						disp.node.unlockable = true;
						disp.node.available = true;
						disp.node.position = pos;
						disp.update(zoom);
						techs.insertLast(disp);
					}
				}
			}

			if(prevCnt == 0)
				panel.centerAround(vec2i(0,0));
			ttip.bringToFront();
		}
	}

	bool onMouseEvent(const MouseEvent& event, IGuiElement@ source) {
		if(event.type == MET_Button_Up && event.button == 0 && !ttip.isAncestorOf(source)) {
			ttip.visible = false;
			if(hovered.x != INT_MAX && hovered.y != INT_MAX)
				showChanger(hovered);
			panel.stopDrag();
			return true;
		}
		else if(event.type == MET_Moved) {
			vec2i relPos = mousePos - panel.AbsolutePosition.topLeft;
			relPos += T_SIZE / 2;
			hovered.y = floor(double(relPos.y) / double(T_SIZE.y - T_SPAC));
			if(hovered.y % 2 != 0)
				relPos.x -= T_SIZE.x / 2;
			hovered.x = floor(double(relPos.x) / double(T_SIZE.x));
		}
		return BaseGuiElement::onMouseEvent(event, source);
	}

	void save() {
		const string fname = path_join(topMod.abspath, "data/research/base_grid.txt");
		ensureFile(fname);
		WriteFile file(fname);
		file.writeKeyValue("Grid", "Base");
		file.indent();

		for(uint i = 0, cnt = techs.length; i < cnt; ++i) {
			auto@ node = techs[i].node;
			if(getCompletion(node.type.ident) is null)
				continue;
			file.writeKeyValue(node.type.ident, ""+node.position.x+","+node.position.y);
		}
	}

	void setNode(const vec2i& pos, const TechnologyType@ type) {
		for(uint i = 0, cnt = techs.length; i < cnt; ++i) {
			if(techs[i].node.position == pos) {
				@techs[i].node.type = type;
				techs[i].update();
				save();
				return;
			}
		}

		TechDisplay disp(panel);
		disp.node.position = pos;
		disp.node.unlocked = false;
		disp.node.bought = false;
		disp.node.unlockable = true;
		disp.node.available = true;
		@disp.node.type = type;

		techs.insertLast(disp);
		disp.update();
		save();
	}

	void deleteNode(const vec2i& pos) {
		for(uint i = 0, cnt = techs.length; i < cnt; ++i) {
			if(techs[i].node.position == pos) {
				techs[i].remove();
				techs.removeAt(i);
				save();
				return;
			}
		}
	}

	bool onGuiEvent(const GuiEvent& event) {
		if(event.type == GUI_Hover_Changed) {
			auto@ disp = cast<TechDisplay>(event.caller);
			if(disp !is null && selected is null) {
				if(!disp.hovered && disp is ttip.tied) {
					ttip.visible = false;
				}
				else {
					ttip.update(disp);
					ttip.visible = true;
				}
				return true;
			}
		}
		else if(event.type == GUI_Clicked) {
			auto@ disp = cast<TechDisplay>(event.caller);
			if(disp !is null) {
				if(!panel.isDragging) {
					if(event.value == 0) {
						showChanger(disp.node.position);
					}
					else if(event.value == 1) {
						deleteNode(disp.node.position);
					}
				}
				panel.stopDrag();
				return true;
			}
		}
		return BaseGuiElement::onGuiEvent(event);
	}

	void draw() {
		ResearchTab::draw();
		if(hovered.x != INT_MAX && hovered.y != INT_MAX) {
			vec2i pos;
			pos.x = hovered.x * T_SIZE.x;
			pos.y = double(hovered.y * (T_SIZE.y - T_SPAC));
			if(hovered.y % 2 != 0)
				pos.x += T_SIZE.x / 2;
			pos -= T_SIZE / 2;

			(spritesheet::TechBase+4).draw(recti_area(pos + panel.AbsolutePosition.topLeft, T_SIZE));
		}
	}

	void showChanger(const vec2i& pos) {
		GuiContextMenu menu(mousePos, width=300);
		menu.itemHeight = 50;

		for(uint i = 0, cnt = techCompletions.length; i < cnt; ++i) {
			auto@ type = makeType(techCompletions[i]);
			menu.addOption(TechnologyItem(this, type, pos));
		}

		menu.finalize();
	}
};

class TechnologyItem : GuiMarkupContextOption {
	const TechnologyType@ type;
	vec2i pos;
	ResearchEditor@ editor;

	TechnologyItem(ResearchEditor@ editor, const TechnologyType@ type, vec2i pos) {
		@this.type = type;
		this.pos = pos;
		@this.editor = editor;

		super(format("[img=$3;40][color=$4][b]$1[/b]\n[offset=20][i]$2[/i][/offset][/color][/img]",
				type.name, type.blurb,
				getSpriteDesc(type.icon),
				toString(type.color)));
	}

	void call(GuiContextMenu@ menu) {
		editor.setNode(pos, type);
	}
}

class ResearchEditorCommand : ConsoleCommand {
	void execute(const string& args) {
		Tab@ editor = ResearchEditor();
		newTab(editor);
		switchToTab(editor);
	}
};

void init() {
	addConsoleCommand("research_editor", ResearchEditorCommand());
}
