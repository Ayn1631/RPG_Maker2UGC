"""Import exact client template structures for the generic 400-control scheduler."""
import argparse
import json
from pathlib import Path

KINDS = {'container', 'textbox', 'image', 'cursor', 'button'}
COLORS = {'imageColor', 'fontColor', 'outlineColor', 'bgColor'}
# Omit save-specific identity and synchronization metadata; the catalog records reusable structure.
OMIT = {'id', 'guid', 'kind', 'sourceFile', 'syncAllDevices'}

def describe(node):
    """Validate one static template subtree and return its stable properties and native-control count."""
    if node['kind'] not in KINDS:
        raise ValueError(f"Unsupported atomic/dynamic template kind: {node['kind']}")
    if node.get('scriptMappingIds'):
        raise ValueError(f"Template scripts allocate outside the exported scheduler: {node['name']}")
    properties = {key: value for key, value in node.items()
                  if key not in OMIT | COLORS and isinstance(value, (str, int, float, bool))}
    colors = {}
    for key in COLORS & node.keys():
        value = node[key]
        if not isinstance(value, int) or not 0 <= value <= 0xffffffff:
            raise ValueError(f'Expected packed ARGB at {node["name"]}.{key}')
        colors[key] = [(value >> 16) & 255, (value >> 8) & 255, value & 255, (value >> 24) & 255]
    children = [describe(child) for child in node.get('children', [])]
    count = 1 + sum(child['count'] for child in children)
    if count > 400:
        raise ValueError(f"Template {node['name']} clones {count} native controls atomically; split it into templates of at most 400")
    return dict(kind=node['kind'], count=count, properties=properties, colors=colors, children=children)

def main():
    """Read a simulator save and write a catalog that the offline builder can validate."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', type=Path, required=True, help='Simulator save with the real client template definitions')
    parser.add_argument('--output', type=Path, required=True, help='Catalog JSON; select it with uiTemplateCatalog in project.lua')
    args = parser.parse_args()
    document = json.loads(args.source.read_text(encoding='utf-8-sig'))
    if document.get('format') != 'qxqy-simulator-save':
        raise ValueError('Expected a qxqy-simulator-save document')
    roots = document['assets']['client']['root']['children']
    templates = {}
    for node in roots:
        template_id = node['guid']
        if not isinstance(template_id, int) or not 1 <= template_id <= 2147483647:
            raise ValueError(f'Invalid template ID: {template_id}')
        key = str(template_id)
        if key in templates:
            raise ValueError(f'Duplicate template ID: {key}')
        templates[key] = describe(node)
    catalog = dict(version=1, source=args.source.as_posix(), templates=templates)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(catalog, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    print(json.dumps({key: value['count'] for key, value in templates.items()}, ensure_ascii=False))

if __name__ == '__main__':
    main()
