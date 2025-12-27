/**
 * Vampire Survivors - Map Editor Pro Logic
 */

class MapEditor {
    constructor() {
        this.config = {
            tw: 128, th: 128, // Tile size in Tileset
            displaySize: 32, // Tile size in Game
            mapW: 32, mapH: 24,
            tilesetPath: '../../assets/tiles/hub_tileset.png'
        };

        this.state = {
            tiles: new Array(this.config.mapW * this.config.mapH).fill(69), // Default background in design
            selectedTile: 10,
            currentTool: 'brush',
            zoom: 1.0,
            offsetX: 50,
            offsetY: 50,
            isMouseDown: false,
            isDragging: false,
            lastX: 0, lastY: 0,
            rectStart: null, // For Rect Fill preview
            history: [],
            historyIndex: -1
        };

        this.assets = {
            tileset: new Image()
        };

        this.canvases = {
            main: document.getElementById('main-canvas'),
            palette: document.getElementById('palette-canvas')
        };

        this.ctx = {
            main: this.canvases.main.getContext('2d'),
            palette: this.canvases.palette.getContext('2d')
        };

        this.init();
    }

    async init() {
        await this.loadAssets();
        this.setupEventListeners();
        this.resize();
        this.renderPalette();
        this.saveHistory();
        this.animate();
    }

    loadAssets() {
        return new Promise((resolve) => {
            this.assets.tileset.src = this.config.tilesetPath;
            this.assets.tileset.onload = () => resolve();
        });
    }

    setupEventListeners() {
        window.addEventListener('resize', () => this.resize());

        // Mouse Events
        this.canvases.main.addEventListener('mousedown', (e) => this.onMouseDown(e));
        window.addEventListener('mousemove', (e) => this.onMouseMove(e));
        window.addEventListener('mouseup', () => this.onMouseUp());
        this.canvases.main.addEventListener('contextmenu', (e) => e.preventDefault());

        // Palette Interaction
        this.canvases.palette.addEventListener('click', (e) => this.onPaletteClick(e));

        // Tool Buttons
        document.querySelectorAll('.tool-btn').forEach(btn => {
            btn.addEventListener('click', () => {
                const tool = btn.id.split('-')[1];
                this.setTool(tool);
            });
        });

        // Key Bindings
        window.addEventListener('keydown', (e) => {
            if (e.ctrlKey && e.key === 'z') this.undo();
            if (e.ctrlKey && e.key === 'y') this.redo();
            if (e.key === 'b') this.setTool('brush');
            if (e.key === 'e') this.setTool('eraser');
            if (e.key === 'g') this.setTool('fill');
            if (e.key === 'i') this.setTool('picker');
        });

        // Zoom (Wheel)
        this.canvases.main.addEventListener('wheel', (e) => {
            if (e.shiftKey) {
                const delta = e.deltaY > 0 ? 0.9 : 1.1;
                this.state.zoom *= delta;
                this.state.zoom = Math.max(0.1, Math.min(5, this.state.zoom));
                e.preventDefault();
            }
        });

        // Export Actions
        document.getElementById('export-btn').addEventListener('click', () => this.exportLua());
        document.getElementById('close-btn').addEventListener('click', () => {
            document.getElementById('modal-export').style.display = 'none';
        });
        document.getElementById('copy-btn').addEventListener('click', () => {
            const textarea = document.getElementById('export-code');
            textarea.select();
            document.execCommand('copy');
            alert('代码已复制到剪贴板！');
        });

        document.getElementById('save-json-btn').addEventListener('click', () => this.saveProject());
        document.getElementById('load-json-btn').addEventListener('click', () => {
            const input = document.createElement('input');
            input.type = 'file';
            input.accept = '.json';
            input.onchange = (e) => this.loadProject(e.target.files[0]);
            input.click();
        });

        document.getElementById('undo-btn').addEventListener('click', () => this.undo());
        document.getElementById('redo-btn').addEventListener('click', () => this.redo());
    }

    resize() {
        const container = document.getElementById('canvas-container');
        this.canvases.main.width = container.clientWidth;
        this.canvases.main.height = container.clientHeight;
    }

    setTool(tool) {
        this.state.currentTool = tool;
        document.querySelectorAll('.tool-btn').forEach(btn => btn.classList.remove('active'));
        document.getElementById(`tool-${tool}`).classList.add('active');
    }

    onMouseDown(e) {
        if (e.button === 1 || (e.button === 0 && e.altKey)) {
            this.state.isDragging = true;
        } else {
            this.state.isMouseDown = true;
            if (this.state.currentTool === 'rect') {
                const { tx, ty } = this.screenToWorld(e.clientX, e.clientY);
                this.state.rectStart = { tx, ty };
            } else {
                this.handleDrawing(e);
            }
        }
        this.state.lastX = e.clientX;
        this.state.lastY = e.clientY;
    }

    onMouseMove(e) {
        const dx = e.clientX - this.state.lastX;
        const dy = e.clientY - this.state.lastY;

        if (this.state.isDragging) {
            this.state.offsetX += dx;
            this.state.offsetY += dy;
        } else if (this.state.isMouseDown) {
            this.handleDrawing(e);
        }

        // Update status bar
        const worldCoords = this.screenToWorld(e.clientX, e.clientY);
        document.getElementById('pos-x').textContent = Math.floor(worldCoords.tx);
        document.getElementById('pos-y').textContent = Math.floor(worldCoords.ty);
        document.getElementById('zoom-level').textContent = Math.round(this.state.zoom * 100) + '%';

        this.state.lastX = e.clientX;
        this.state.lastY = e.clientY;
    }

    onMouseUp() {
        if (this.state.isMouseDown) {
            if (this.state.currentTool === 'rect' && this.state.rectStart) {
                this.applyRectFill();
            }
            this.saveHistory();
        }
        this.state.isMouseDown = false;
        this.state.isDragging = false;
        this.state.rectStart = null;
    }

    applyRectFill() {
        // Find current tx, ty from mouseup point
        const { tx: ex, ty: ey } = this.screenToWorld(this.state.lastX, this.state.lastY);
        const { tx: sx, ty: sy } = this.state.rectStart;

        const minX = Math.min(sx, ex), maxX = Math.max(sx, ex);
        const minY = Math.min(sy, ey), maxY = Math.max(sy, ey);

        for (let y = minY; y <= maxY; y++) {
            for (let x = minX; x <= maxX; x++) {
                if (x >= 0 && x < this.config.mapW && y >= 0 && y < this.config.mapH) {
                    this.state.tiles[y * this.config.mapW + x] = this.state.selectedTile;
                }
            }
        }
    }

    screenToWorld(sx, sy) {
        const rect = this.canvases.main.getBoundingClientRect();
        const x = (sx - rect.left - this.state.offsetX) / this.state.zoom;
        const y = (sy - rect.top - this.state.offsetY) / this.state.zoom;
        return {
            x, y,
            tx: Math.floor(x / this.config.displaySize),
            ty: Math.floor(y / this.config.displaySize)
        };
    }

    handleDrawing(e) {
        const { tx, ty } = this.screenToWorld(e.clientX, e.clientY);
        if (tx < 0 || tx >= this.config.mapW || ty < 0 || ty >= this.config.mapH) return;

        const idx = ty * this.config.mapW + tx;

        switch (this.state.currentTool) {
            case 'brush':
                this.state.tiles[idx] = this.state.selectedTile;
                break;
            case 'eraser':
                this.state.tiles[idx] = 69; // Changed to match user preference (Background/Void)
                break;
            case 'picker':
                this.state.selectedTile = this.state.tiles[idx];
                document.getElementById('current-tile-id').textContent = this.state.selectedTile;
                this.renderPalette();
                break;
            case 'fill':
                this.floodFill(tx, ty, this.state.tiles[idx], this.state.selectedTile);
                break;
        }
    }

    floodFill(x, y, target, replacement) {
        if (target === replacement) return;
        const index = (y * this.config.mapW + x);
        if (this.state.tiles[index] !== target) return;

        const stack = [[x, y]];
        while (stack.length > 0) {
            const [cx, cy] = stack.pop();
            const cIdx = cy * this.config.mapW + cx;
            if (this.state.tiles[cIdx] === target) {
                this.state.tiles[cIdx] = replacement;
                if (cx > 0) stack.push([cx - 1, cy]);
                if (cx < this.config.mapW - 1) stack.push([cx + 1, cy]);
                if (cy > 0) stack.push([cx, cy - 1]);
                if (cy < this.config.mapH - 1) stack.push([cx, cy + 1]);
            }
        }
    }

    onPaletteClick(e) {
        const rect = this.canvases.palette.getBoundingClientRect();
        const x = e.clientX - rect.left;
        const y = e.clientY - rect.top;

        const size = 32 + 4;
        const col = Math.floor(x / size);
        const row = Math.floor(y / size);
        const idx = row * 4 + col + 1;

        if (idx <= 64) {
            this.state.selectedTile = idx + 9; // Map to Game ID (10, 11...)
            document.getElementById('current-tile-id').textContent = this.state.selectedTile;
            this.renderPalette();
        }
    }

    renderPalette() {
        const ctx = this.ctx.palette;
        this.canvases.palette.width = 4 * (32 + 4);
        this.canvases.palette.height = 16 * (32 + 4);

        ctx.clearRect(0, 0, 300, 1000);
        const size = 32;
        const margin = 4;
        const tw = 128;

        for (let i = 0; i < 64; i++) {
            const col = i % 4;
            const row = Math.floor(i / 4);
            const dx = col * (size + margin);
            const dy = row * (size + margin);

            const sx = (i % 8) * tw;
            const sy = Math.floor(i / 8) * tw;

            ctx.drawImage(this.assets.tileset, sx, sy, tw, tw, dx, dy, size, size);

            if (this.state.selectedTile === i + 10) {
                ctx.strokeStyle = '#ffff00';
                ctx.lineWidth = 2;
                ctx.strokeRect(dx, dy, size, size);
            }
        }
    }

    saveHistory() {
        const snapshot = JSON.stringify(this.state.tiles);
        if (this.state.historyIndex >= 0 && this.state.history[this.state.historyIndex] === snapshot) return;

        this.state.history = this.state.history.slice(0, this.state.historyIndex + 1);
        this.state.history.push(snapshot);
        this.state.historyIndex++;

        if (this.state.history.length > 50) {
            this.state.history.shift();
            this.state.historyIndex--;
        }
    }

    undo() {
        if (this.state.historyIndex > 0) {
            this.state.historyIndex--;
            this.state.tiles = JSON.parse(this.state.history[this.state.historyIndex]);
        }
    }

    redo() {
        if (this.state.historyIndex < this.state.history.length - 1) {
            this.state.historyIndex++;
            this.state.tiles = JSON.parse(this.state.history[this.state.historyIndex]);
        }
    }

    animate() {
        this.render();
        requestAnimationFrame(() => this.animate());
    }

    render() {
        const ctx = this.ctx.main;
        const { main: canvas } = this.canvases;

        ctx.fillStyle = '#050505';
        ctx.fillRect(0, 0, canvas.width, canvas.height);

        ctx.save();
        ctx.translate(this.state.offsetX, this.state.offsetY);
        ctx.scale(this.state.zoom, this.state.zoom);

        // Draw Map Tiles
        const ts = this.config.displaySize;
        const tw = this.config.tw;

        for (let y = 0; y < this.config.mapH; y++) {
            for (let x = 0; x < this.config.mapW; x++) {
                const tile = this.state.tiles[y * this.config.mapW + x];
                let sx, sy;

                if (tile === 0) { sx = 0; sy = 0; }
                else if (tile === 2) { sx = 0; sy = tw; }
                else if (tile === 3) { sx = 0; sy = tw * 2; }
                else if (tile === 1) { sx = 0; sy = tw * 3; }
                else if (tile >= 10) {
                    const idx = tile - 10;
                    sx = (idx % 8) * tw;
                    sy = Math.floor(idx / 8) * tw;
                }

                ctx.drawImage(this.assets.tileset, sx, sy, tw, tw, x * ts, y * ts, ts, ts);
            }
        }

        // Draw Grid
        ctx.strokeStyle = 'rgba(255, 255, 255, 0.05)';
        ctx.lineWidth = 1 / this.state.zoom;
        ctx.beginPath();
        for (let x = 0; x <= this.config.mapW; x++) {
            ctx.moveTo(x * ts, 0); ctx.lineTo(x * ts, this.config.mapH * ts);
        }
        for (let y = 0; y <= this.config.mapH; y++) {
            ctx.moveTo(0, y * ts); ctx.lineTo(this.config.mapW * ts, y * ts);
        }
        ctx.stroke();

        // Draw Rect Preview
        if (this.state.isMouseDown && this.state.currentTool === 'rect' && this.state.rectStart) {
            const { tx: sx, ty: sy } = this.state.rectStart;
            const { tx: ex, ty: ey } = this.screenToWorld(this.state.lastX, this.state.lastY);
            const minX = Math.min(sx, ex), maxX = Math.max(sx, ex);
            const minY = Math.min(sy, ey), maxY = Math.max(sy, ey);

            ctx.fillStyle = 'rgba(0, 162, 255, 0.3)';
            ctx.strokeStyle = '#00a2ff';
            ctx.lineWidth = 2 / this.state.zoom;
            ctx.fillRect(minX * ts, minY * ts, (maxX - minX + 1) * ts, (maxY - minY + 1) * ts);
            ctx.strokeRect(minX * ts, minY * ts, (maxX - minX + 1) * ts, (maxY - minY + 1) * ts);
        }

        ctx.restore();
    }

    saveProject() {
        const data = {
            config: this.config,
            tiles: this.state.tiles
        };
        const blob = new Blob([JSON.stringify(data, null, 2)], { type: 'application/json' });
        const url = URL.createObjectURL(blob);
        const a = document.createElement('a');
        a.href = url;
        a.download = `map_project_${Date.now()}.json`;
        a.click();
    }

    loadProject(file) {
        if (!file) return;
        const reader = new FileReader();
        reader.onload = (e) => {
            const data = JSON.parse(e.target.result);
            this.state.tiles = data.tiles;
            this.saveHistory();
        };
        reader.readAsText(file);
    }

    exportLua() {
        const { mapW, mapH } = this.config;
        let code = 'local mapData = {\n';
        code += `    w = ${mapW},\n`;
        code += `    h = ${mapH},\n`;
        code += '    tiles = {\n';

        for (let y = 0; y < mapH; y++) {
            const row = [];
            for (let x = 0; x < mapW; x++) {
                row.push(this.state.tiles[y * mapW + x]);
            }
            code += `        ${row.join(', ')},\n`;
        }

        code += '    }\n}';

        document.getElementById('export-code').value = code;
        document.getElementById('modal-export').style.display = 'flex';
    }
}

document.addEventListener('DOMContentLoaded', () => {
    window.editor = new MapEditor();
});
