let settings = RenderSettings {
    level: Level::new(),
    num_threads: 0,
    render_mode: RenderMode::OptimizeSpeed,
};

let mut ctx = RenderContext::new_with(100, 100, settings);

// Draw different shapes in various colors.
ctx.set_paint(BLUE);
ctx.fill_path(&Rect::new(25.0, 25.0, 75.0, 75.0).to_path(0.1));
ctx.set_paint(RED.with_alpha(0.5));
ctx.fill_path(&Rect::new(50.0, 50.0, 85.0, 85.0).to_path(0.1));
ctx.set_paint(GREEN);
ctx.stroke_path(&Circle::new((50.0, 50.0), 30.0).to_path(0.1));

// Flush all existing operations (only necessary for multi-threaded rendering).
ctx.flush();

let mut pixmap = Pixmap::new(100, 100);
// Render the results to a pixmap.
ctx.render_to_pixmap(&mut pixmap);

// Encode the pixmap into a PNG file.
let png = pixmap.into_png().unwrap();