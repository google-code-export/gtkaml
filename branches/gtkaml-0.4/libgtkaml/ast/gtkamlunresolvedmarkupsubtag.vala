using GLib;
using Vala;

/**
 * Any markup tag encountered in XML that is not the root, nor has g:public/g:private identifier.
 * Can later morph into a complex attribute
 */
public class Gtkaml.UnresolvedMarkupSubTag : MarkupSubTag {

	public override string me { get { assert_not_reached(); return ":D"; } }

	public UnresolvedMarkupSubTag (MarkupTag parent_tag, string tag_name, MarkupNamespace tag_namespace, SourceReference? source_reference = null)
	{
		base (parent_tag, tag_name, tag_namespace, source_reference);
	}	
	
	public override void generate_public_ast () {
		//No public AST for future temps or attributes
	}
	
	public override void resolve (MarkupResolver resolver) {
		bool is_attribute = false;
		if (!tag_namespace.explicit_prefix && markup_attributes.size == 0)  { //candidate for attribute
			ObjectTypeSymbol parent_data_type = parent_tag.resolved_type.data_type as ObjectTypeSymbol;
			if (parent_data_type != null) {
				//search through properties
				foreach (Property p in parent_data_type.get_properties ()) {
					if (p.name == tag_name) {
						//TODO: transform this into attribute
						stderr.printf ("found attribute %s", p.name);
						is_attribute = true;
						break;
					}
				}
			}
			//TODO: search through fields
		}
		
		if (!is_attribute) {
			//TODO:replace unresolved tags with temp tags or complex attributes	
			var markup_temp = new MarkupTemp (parent_tag, tag_name, tag_namespace, source_reference);
			parent_tag.replace_child_tag (this, markup_temp);
			markup_temp.generate_public_ast (); //catch up with others
			markup_temp.resolve (resolver);
		}
	}
	
	public override void generate (MarkupResolver resolver) {
		assert_not_reached ();//unresolved tags are replaced with temporary variables or complex attributes at resolve () time
	}
}
