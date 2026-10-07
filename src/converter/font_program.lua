-- Offline validated font bank -> portable private factory source, not bytecode.
return function(deps)
 local runs=deps['runtime.ui.font_run'];local serialize=deps['build.serialize'];local M={}
 function M.compile(faces)
  local bank=runs.compile(faces);local stats={faces=#bank.faces,glyphs=0,mappings=0,scripts=0,layouts=0,lookups=0,points=0}
  for _,f in ipairs(bank.faces)do
   for _,g in pairs(f.glyphs)do stats.glyphs=stats.glyphs+1;stats.points=stats.points+g.outline.pointCount end
   for _ in pairs(f.map)do stats.mappings=stats.mappings+1 end
   for _ in pairs(f.proofs or f.selections)do stats.scripts=stats.scripts+1 end
   if f.layout then stats.layouts=stats.layouts+1;stats.lookups=stats.lookups+#f.layout.lookups end
  end
  -- One bank literal per factory, including one layout per face. Only newMain
  -- escapes; neither raw faces nor a writable bank alias is returned.
  local literal=serialize.literal(bank)
  local source="-- Offline validated main-font program. No runtime file loader.\nreturn function(deps)\n local sourceText=deps['runtime.ui.source_text']\n local bank="..literal.."\n return{newMain=function()return sourceText.newCompiled(bank)end}\nend\n"
  stats.bytes=#source
  return{kind='r2u.font-program',schemaVersion=1,moduleId='generated.ui_fonts',dependencies={'runtime.ui.source_text'},source=source,stats=stats}
 end
 return M
end
