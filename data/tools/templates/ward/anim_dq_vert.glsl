varying vec3 N_frag,dPds_frag,dPdt_frag;
varying vec2 st_frag;
varying vec3 V_frag;

vec3 QuatTransformVector(vec4 Q,vec3 v){
	return v + 2.0*cross(Q.xyz, cross(Q.xyz,v) + Q.w*v);
}

vec4 QuatMul(vec4 a,vec4 b){
	return vec4(a.w*b.xyz+b.w*a.xyz-cross(a.xyz,b.xyz),a.w*b.w-dot(a.xyz,b.xyz));
}

void ComputeTransformLinear(out vec3 R048,out vec3 R372,out vec3 R156,out vec3 T,out float S, out vec4 Q_hack){
	// Q_hack is in fact not consistent with the position transformation, but it should work for our purpose
	// Do not Use SKEL0[i] directly in texture2D. Because it triggers an error on Meizu MX5.
	vec3 x2y2z2=vec3(0.0);
	vec3 R372_plus_156=vec3(0.0);
	vec3 R372_minus_156=vec3(0.0);
	T=vec3(0.0);
	S=0.0;
	vec4 skel_id = SKEL0;
	vec4 skel_weight = WEIGHT0;
	Q_hack=vec4(0.0);
	for (int i = 0; i < 4; i++) {
		#ifdef USE_VTF
		vec4 Q = texture2DLod(tex_deform, vec2((2.0 * fid + 0.5) / deform_width, skel_id[i]), 0.0);
		#else
		vec4 Q = arrvec4_deform[int(skel_id[i] * cluster_num - 0.0) * 2 + 0];
		#endif
		vec4 weighted_Q=skel_weight[i]*Q;
		x2y2z2+=weighted_Q.xyz*Q.xyz;
		R372_plus_156+=weighted_Q.xyz*Q.yzx;
		R372_minus_156+=Q.w*weighted_Q.zxy;
		#ifdef USE_VTF
		vec4 dq2 = texture2DLod(tex_deform, vec2((2.0 * fid + 1.5) / deform_width, skel_id[i]), 0.0);
		#else
		vec4 dq2 = arrvec4_deform[int(skel_id[i] * cluster_num - 0.0) * 2 + 1];
		#endif
		T+=skel_weight[i]*dq2.xyz;
		if(dq2.w<0.1) dq2.w = 1.0;
		S+=skel_weight[i]*dq2.w;
		Q_hack+=weighted_Q;
	}
	
	R048=1.0+(-2.0)*(x2y2z2.yxx+x2y2z2.zzy);
	R372=2.0*(R372_plus_156+R372_minus_156);
	R156=2.0*(R372_plus_156-R372_minus_156);
}

vec3 ComputeBoneTranslate(float bone) {
	#ifdef USE_VTF
	vec3 T = texture2DLod(tex_deform, vec2((2.0 * fid + 1.5) / deform_width, bone), 0.0).xyz;
	#else
	vec3 T = arrvec4_deform[int(bone * cluster_num - 0.0) * 2 + 1].xyz;
	#endif
	return T;
}

vec3 LinearTransformVector(vec3 R048,vec3 R372,vec3 R156,vec3 v){
	return v*R048+v.yzx*R156+(v*R372).zxy;
}

void QuatToMatrix(out vec3 R048,out vec3 R372,out vec3 R156,vec4 Q){
	vec3 x2y2z2=Q.xyz*Q.xyz;
	vec3 R372_plus_156=Q.xyz*Q.yzx;
	vec3 R372_minus_156=Q.w*Q.zxy;
	R048=1.0+(-2.0)*(x2y2z2.yxx+x2y2z2.zzy);
	R372=2.0*(R372_plus_156+R372_minus_156);
	R156=2.0*(R372_plus_156-R372_minus_156);
}


void main(){
	mat4 vpMat = mat_proj * mat_view;
	vec3 P1 = P;

	mat3 rotMat = mat3(rot_mat1,rot_mat2,rot_mat3);

	P1 *= scales;
	vec3 Nr = N;

	vec4 Pb=vec4(P1,1.0);
	vec4 N1=vec4(Nr, 0.0);
	vec3 P2=vec3(0.0);
	vec3 N2=vec3(0.0);

	vec4 dPs1 = vec4(dPds, 0.0);
	vec4 dPt1 = vec4(dPdt, 0.0);
	vec3 dPs2 = vec3(0.0);
	vec3 dPt2 = vec3(0.0);

	//bone transform
	vec3 drt = vec3(0.0);
	if (animating == 1.0) {
		vec3 R048,R372,R156,T;
		float S;
		vec4 Q_hack;
		vec3 Pv3 = P1; vec3 Nv3 = N;
		vec3 dPdsv3 = dPds; vec3 dPdtv3 = dPdt;
		ComputeTransformLinear(R048,R372,R156,T,S,Q_hack);
		
		Pv3 *= vec3(S);
		P2 = T+LinearTransformVector(R048,R372,R156,Pv3);
		N2 = LinearTransformVector(R048,R372,R156,Nv3);
		dPs2 = LinearTransformVector(R048,R372,R156,dPdsv3);
		dPt2 = LinearTransformVector(R048,R372,R156,dPdtv3);
		drt = ComputeBoneTranslate(rootBone);
	} else {
		P2 = Pb.xyz;
		N2 = N1.xyz;
		dPs2 = dPs1.xyz;
		dPt2 = dPt1.xyz;
	}

	if(isFlipH>0.5){
		P2.x = -P2.x-7.364;
	}

	P2 = scale_e * P2;

	//model transform
	P2 -= drt;
	P2 = rotMat*P2;
	P2 += drt;
	N2 = rotMat*N2;
	
	P2 = (vec4(trans_pos, 0.0) + vec4(P2, 1.0)).xyz;
	N2 = (vec4(N2, 0.0)).xyz;

	P2.z = -P2.z;
	//weight transform
	if(0.5<obj_type&&obj_type<=0.75){
		vec4 head_quat;
		head_quat=vec4(0.0,0.0,0.0,1.0)-quatR1;
		head_quat=quatR1+weight*head_quat;
		P2 -= weightOffset;
		P2 = QuatTransformVector(head_quat,P2);
		P2 += weightOffset;
		vpMat = mat_proj * mat_cam;
	}else 
		vpMat = mat_proj * mat_view;
	gl_Position= vpMat * vec4(P2, 1.0);
	
	vec4 Pf = vec4(P2,1.0);
	V_frag=normalize((mat_view*Pf).xyz);
		
	if(isFlipH>0.5){
		N_frag=normalize((mat_view*vec4(-N2.x,N2.y,-N2.z,0.0)).xyz);
		dPds_frag=normalize((mat_view*vec4(-dPs2.x,dPs2.y,-dPs2.z,0.0)).xyz);
		dPdt_frag=normalize((mat_view*vec4(-dPt2.x,dPt2.y,-dPt2.z,0.0)).xyz);
	}else{
		N_frag=normalize((mat_view*vec4(N2.x,N2.y,-N2.z,0.0)).xyz);
		dPds_frag=normalize((mat_view*vec4(dPs2.x,dPs2.y,-dPs2.z,0.0)).xyz);
		dPdt_frag=normalize((mat_view*vec4(dPt2.x,dPt2.y,-dPt2.z,0.0)).xyz);
	}
	st_frag=st;
	st_frag.y = 1.0 - st_frag.y;
	st_frag=lbrt.xy + (lbrt.zw-lbrt.xy)*st_frag;
	st_frag.y = 1.0 - st_frag.y;
}
