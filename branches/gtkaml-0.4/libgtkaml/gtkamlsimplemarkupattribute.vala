using GLib;
using Vala;

/**
 * Represents an attribute of a MarkupTag
 */
public class Gtkaml.SimpleMarkupAttribute : Object, MarkupAttribute {
	public string attribute_name {get { return _attribute_name; }}
	public Expression attribute_expression { get { return _attribute_expression; }}
	public DataType target_type { get; set; }

	private SourceReference? source_reference;
	private string _attribute_name;
	private Expression _attribute_expression;

	public string? attribute_value {get; private set;}
	
	public SimpleMarkupAttribute (string attribute_name, string? attribute_value, SourceReference? source_reference = null) {
		this._attribute_name = attribute_name;
		this.attribute_value = attribute_value;
		this.source_reference = source_reference;
	}

	public SimpleMarkupAttribute.with_type (string attribute_name, string? attribute_value, DataType target_type, SourceReference? source_reference = null) {
		this._attribute_name = attribute_name;
		this.attribute_value = attribute_value;
		this.target_type = target_type;
	}
	
	public Expression get_expression () {
		assert (target_type != null);
		if (target_type.data_type.get_full_name () == "string")
			return new StringLiteral ("\"" + attribute_value + "\"", source_reference);
		assert_not_reached();
	}


}

